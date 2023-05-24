require("yaci")
require("strict")

CPty = newclass("CPty")

-- in: string
--      Command to run.
-- out: boolean
--      Indicates if terminal was spawned successfully.
function CPty:start(cmd)
    return false
end

-- in: number
--      Number of milliseconds to wait for data become available.
-- out: string, boolean
--      Data recieved from terminal output (stdout + stderr). Empty string is returned if no data available.
--      Indicates if read/check was succesfull. Return false if error occured and terminal should be closed.
function CPty:get_data(timeout)
    return '', false
end

-- in: string
--      Data to send to the terminal input.
-- out: nil
function CPty:send_input(s)
    return
end

-- in: nil
-- out: nil
function CPty:close()
    return
end
