require("yaci")
require("ptys.pty")

local ffi  = require("ffi")

ffi.cdef [[
    typedef int mode_t;
    typedef int32_t pid_t;
    typedef uint32_t nfds_t;

    int kill(pid_t pid, int sig);
    pid_t wait(int *wstatus);
    pid_t fork(void);
    pid_t setsid(void);

    int execvp(const char *file, char *const argv[]);

    int open(const char* pathname, int flags, ...);

    int close(int fd);
    int dup2(int oldfd, int newfd);

    ssize_t read(int fd, void *buf, size_t count);
    ssize_t write(int fildes, const void *buf, size_t nbyte);

    struct winsize {
        unsigned short ws_row;
        unsigned short ws_col;
        unsigned short ws_xpixel;   /* unused */
        unsigned short ws_ypixel;   /* unused */
    };

    int ioctl(int fd, int cmd, ...);
    char* ptsname(int fd);
    int grantpt(int fd);
    int unlockpt(int fd);

    int openpty(int* aprimary, int* areplica, char* name,
              void* termp,
              const struct winsize *winp);
    int login_tty(int fd);

    struct pollfd {
        int fd;
        short int events;
        short int revents;
    };
    int poll(struct pollfd *fds, nfds_t nfds, int timeout);
]]

EBUSY = 16

CUnixPty = newclass("CUnixPty", CPty)

function CUnixPty:init()
    __log.debug("init CUnixPty")
    self.pty = nil
    self.shell_pid = 0
    self.closed = false
end

function CUnixPty:start(cmd)
    __log.debug("start CUnixPty")

    local winsize = ffi.new("struct winsize [1]")
    winsize[0].ws_row = 35
    winsize[0].ws_col = 120

    if ffi.os == "OSX" then
        return self:start_bsd(cmd, winsize)
    end

    -- openpty(),loginpty() are only defined in BSD systems by default, so need to differentiate.
    return self:start_linux(cmd, winsize)
end

function CUnixPty:start_linux(cmd, winsize)
    local O_RDWR = 0x2
    local O_NOCTTY = 0x100

    local primary_fd = ffi.C.open("/dev/ptmx", O_RDWR, 0)

    if primary_fd == -1 then
        __log.errorf("cUnixPty: failed to open /dev/ptmx with error %d", ffi.errno())
        return false
    end

    local grant_res = ffi.C.grantpt(primary_fd)
    if grant_res == -1 then
        __log.errorf("cUnixPty: granpt(%d) failed with error: %d", primary_fd, ffi.errno())
        return false
    end

    local unlock_res = ffi.C.unlockpt(primary_fd)
    if unlock_res == -1 then
        __log.errorf("cUnixPty: unlockpt(%d) failed with error: %d", primary_fd, ffi.errno())
        return false
    end

    local ptsname = ffi.C.ptsname(primary_fd)
    if ptsname == nil then
        __log.errorf("cUnixPty: failed to get ptsname for follower tmux with error %d", ffi.errno())
        return false
    end

    local replica_fd = ffi.C.open(ptsname, O_RDWR + O_NOCTTY, 0)
    if replica_fd == -1 then
        __log.errorf("cUnixPty: failed to open %s with error %d", ffi.string(ptsname), ffi.errno())
        return false
    end

    local TIOCSWINSZ = 0x5414

    if ffi.C.ioctl(replica_fd, TIOCSWINSZ, winsize) == -1 then
        __log.errorf("cUnixPty: failed to set windows size using ioctl(%d): %d", TIOCSWINSZ, ffi.errno())
    end

    self.pty = primary_fd
    return self:spawn_shell(cmd, replica_fd)
end

function CUnixPty:start_bsd(cmd, winsize)
    local primary = ffi.new("int[1]")
    local replica = ffi.new("int[1]")

    if ffi.C.openpty(primary, replica, nil, nil, winsize) == -1 then
        __log.errorf("cUnixPty: failed to call openpty() with errno: %d", ffi.errno())
        return false
    end


    self.pty = primary[0]
    return self:spawn_shell(cmd, replica[0])
end

function CUnixPty:get_data(timeout)
    local POLLIN = 0x0001
    local POLLPRI = 0x0002

    local to_poll = ffi.new("struct pollfd [1]")
    to_poll[0].fd = self.pty
    to_poll[0].events = POLLIN + POLLPRI

    local num_ready = ffi.C.poll(to_poll, 1, timeout)

    if num_ready > 0 then
        local buffer=ffi.new("char[?]", 10240)
        local read = ffi.C.read(self.pty, buffer, 10240)
        if read == -1 and ffi.errno() ~= EBUSY then
            __log.errorf("cUnixPty: failed to read bytes from tty: %d", ffi.errno())
            return '', false
        end

        return ffi.string(buffer, read), true
    end
    return '', true
end

function CUnixPty:send_input(s)
    local c_str = ffi.new("char[?]", #s + 1)
    c_str[#s] = 0
    ffi.copy(c_str, s)
    local bytes_w = ffi.C.write(self.pty, c_str, #s)
    if bytes_w == -1 then
        __log.errorf("cUnixPty: failed to write bytes to tty: %d", ffi.errno())
    end
end

function CUnixPty:close()
    if self.closed then
        __log.infof("cUnixPty: attempt to close pty that is already closed")
        return
    end

    if self.pty ~= nil then
        if ffi.C.close(self.pty) == -1 then
            __log.errorf("cUnixPty: failed to close pty fd with error %d", ffi.errno())
        end
        self.pty = nil
    end

    -- send a sigkill
    local status = ffi.new("int [1]")
    if self.shell_pid > 0 then
        if ffi.C.kill(-self.shell_pid, 9) == -1 then
            __log.errorf("cUnixPty: failed to send SIGKILL to process %d with error %d", -self.shell_pid, ffi.errno())
            -- waiting for process may freeze the agent, so we should not wait if process wasn't killed.
            return
        end
        self.shell_pid = 0
    end

    if ffi.C.wait(status) == -1 then
        __log.errorf("cUnixPty: failed to wait() with error %d", ffi.errno())
    end

    self.closed = true
end

function CUnixPty:spawn_shell(cmd, pty_fd)
    local pid = ffi.C.fork()
    if pid < 0  then
        __log.errorf("fork failed with error %d", ffi.errno())
        return false
    elseif pid == 0 then -- child process
        if ffi.C.close(self.pty) == -1 then
            __log.errorf("cUnixPty: failed to close primary pty fd from child process, errno = %d", ffi.errno())
        end

        if self:login_tty(pty_fd) == -1 then
            __log.errorf("cUnixPty: login_tty failed with errno: %d", ffi.errno())
        end


        local argv = ffi.new("const char* [?]", 2)
        argv[0] = cmd
        argv[1] = nil
        local char_p_k_p_t   = ffi.typeof('char * const *')

        local res = ffi.C.execvp(cmd, ffi.cast(char_p_k_p_t, argv))
        if res == -1 then
            __log.errorf("cUnixPty: execvp(%s) failed with errorno =  %d", cmd, ffi.errno())
            return false
        end
        -- this line should never be reached.
        return true
    end
    self.shell_pid = pid
    ffi.C.close(pty_fd)
    return true
end

function CUnixPty:login_tty(pty_fd)
    if ffi.os == "OSX" then
        return ffi.C.login_tty(pty_fd)
    end

    if ffi.C.setsid() == -1 then
        __log.errorf("cUnixPty: setsid failed with errno: %d", ffi.errno())
        return -1
    end

    local TIOCSCTTY = 0x540E

    if ffi.C.ioctl(pty_fd, TIOCSCTTY, 0) == -1 then
        __log.errorf("cUnixPty: failed to ioctl with error %d", ffi.errno())
        return -1
    end

    while (ffi.C.dup2(pty_fd, 0) == -1) and ffi.errno() == EBUSY do end
    while (ffi.C.dup2(pty_fd, 1) == -1) and ffi.errno() == EBUSY do end
    while (ffi.C.dup2(pty_fd, 2) == -1) and ffi.errno() == EBUSY do end

    if (pty_fd > 2) then
        ffi.C.close(pty_fd)
    end

    return 0
end
