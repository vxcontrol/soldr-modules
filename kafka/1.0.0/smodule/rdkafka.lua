local ffi = require "ffi"

ffi.cdef[[
	typedef struct rd_kafka_s rd_kafka_t;
	typedef struct rd_kafka_conf_s rd_kafka_conf_t;
	typedef struct rd_kafka_topic_s rd_kafka_topic_t;
	typedef struct rd_kafka_topic_conf_s rd_kafka_topic_conf_t;

	typedef enum rd_kafka_type_t {
	        RD_KAFKA_PRODUCER,
	        RD_KAFKA_CONSUMER,
	} rd_kafka_type_t;

	typedef enum { RD_KAFKA_CONF_OK = 0 } rd_kafka_conf_res_t;

	typedef enum { RD_KAFKA_RESP_ERR_NO_ERROR = 0 } rd_kafka_resp_err_t;

	typedef struct rd_kafka_message_s {
	        rd_kafka_resp_err_t err;
	        rd_kafka_topic_t *rkt;
	        int32_t partition;
	        void *payload;
	        size_t len;
	        void *key;
	        size_t key_len;
	        int64_t offset;
	        void *_private;
	} rd_kafka_message_t;

	const char *rd_kafka_err2str(rd_kafka_resp_err_t err);

	// Configuration

	rd_kafka_conf_t *rd_kafka_conf_new(void);
	rd_kafka_conf_t *rd_kafka_conf_dup(const rd_kafka_conf_t *conf);
	void rd_kafka_conf_destroy(rd_kafka_conf_t *conf);
	rd_kafka_conf_res_t rd_kafka_conf_set(rd_kafka_conf_t *conf,
	                                      const char *name,
	                                      const char *value,
	                                      char *errstr,
	                                      size_t errstr_size);
	void rd_kafka_conf_set_dr_msg_cb(
	    rd_kafka_conf_t *conf,
	    void (*dr_msg_cb)(rd_kafka_t *rk,
	                      const rd_kafka_message_t *rkmessage,
	                      void *opaque));
	void rd_kafka_conf_set_error_cb(rd_kafka_conf_t *conf,
	                                void (*error_cb)(rd_kafka_t *rk,
	                                                 int err,
	                                                 const char *reason,
	                                                 void *opaque));
	void rd_kafka_conf_set_log_cb(rd_kafka_conf_t *conf,
	                              void (*log_cb)(const rd_kafka_t *rk,
	                                             int level,
	                                             const char *fac,
	                                             const char *buf));

	// Kafka

	rd_kafka_t *rd_kafka_new(rd_kafka_type_t type,
	                         rd_kafka_conf_t *conf,
	                         char *errstr,
	                         size_t errstr_size);
	void rd_kafka_destroy(rd_kafka_t *rk);
	rd_kafka_resp_err_t rd_kafka_flush(rd_kafka_t *rk, int timeout_ms);
	int rd_kafka_poll(rd_kafka_t *rk, int timeout_ms);

	// Topic

	rd_kafka_topic_t *rd_kafka_topic_new(rd_kafka_t *rk,
		                                   const char *topic,
		                                   rd_kafka_topic_conf_t *conf);
	void rd_kafka_topic_destroy(rd_kafka_topic_t *rkt);
	const char *rd_kafka_topic_name(const rd_kafka_topic_t *rkt);


	// Produce

	enum { RD_KAFKA_PARTITION_UA = -1 };
	enum { RD_KAFKA_MSG_F_COPY = 0x2 };

	int rd_kafka_produce(rd_kafka_topic_t *rkt,
	                     int32_t partition,
	                     int msgflags,
	                     void *payload,
	                     size_t len,
	                     const void *key,
	                     size_t keylen,
	                     void *msg_opaque);
]]
local K = ffi.load("librdkafka.so.1")

local ERRLEN = 1024

-- :: rd_kafka_resp_err_t -> number, string
local function from_resp_err(err)
	local errstr = K.rd_kafka_err2str(err)
	return tonumber(err), ffi.string(errstr)
end


local Config = {}; Config.__index = Config

-- Configuration properties:
-- https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md
-- :: {propertyA: valueA, ...} -> Config
function Config.new(props)
	local conf = K.rd_kafka_conf_new()
	ffi.gc(conf, K.rd_kafka_conf_destroy)

	local errstr = ffi.new("char[?]", ERRLEN)
	for name, value in pairs(props) do
		local err = K.rd_kafka_conf_set(conf, name, value, errstr, ERRLEN)
		assert(err == K.RD_KAFKA_CONF_OK, ffi.string(errstr))
	end

	return setmetatable({_conf=conf}, Config)
end

-- :: (code::number, message::string -> ()) -> ()
function Config:on_error(cb)
	self._error_cb = cb

	-- Disable the default logger.
	K.rd_kafka_conf_set_log_cb(self._conf, nil)

	K.rd_kafka_conf_set_dr_msg_cb(self._conf, function(rk, rkm, opaque)
		if rkm.err ~= K.RD_KAFKA_RESP_ERR_NO_ERROR then
			local topic = ffi.string(K.rd_kafka_topic_name(rkm.rkt))
			local code, msg = from_resp_err(rkm.err)
			cb(code, "topic="..topic..": "..msg)
		end
	end)

	K.rd_kafka_conf_set_error_cb(self._conf, function(rk, err, reason, opaque)
		cb(tonumber(err), ffi.string(reason))
	end)
end

local Producer = {}; Producer.__index = Producer

-- Create a producer with the given configuration.
-- :: Config -> Producer
function Producer.new(config)
	local errstr = ffi.new("char[?]", ERRLEN)

	local conf = K.rd_kafka_conf_dup(config._conf)
	ffi.gc(conf, K.rd_kafka_conf_destroy)

	local rk = K.rd_kafka_new(K.RD_KAFKA_PRODUCER, conf, errstr, ERRLEN)
	assert(rk, ffi.string(errstr))
	ffi.gc(rk, K.rd_kafka_destroy)
	ffi.gc(conf, nil)

	return setmetatable({
		_rk = rk,
		_error_cb = config._error_cb,
	}, Producer)
end

function Producer:destroy()
	if self._rk then
		K.rd_kafka_destroy(ffi.gc(self._rk, nil))
		self._rk = nil
	end
end

-- :: mseconds -> boolean
function Producer:flush(timeout_ms)
	assert(self._rk, "bad kafka handle")
	local err = K.rd_kafka_flush(self._rk, timeout_ms)
	if err ~= K.RD_KAFKA_RESP_ERR_NO_ERROR then
		if self._error_cb then self._error_cb(from_resp_err(err)) end
		return false
	end
	return true
end

-- :: mseconds? -> number
function Producer:poll(timeout_ms)
	assert(self._rk, "bad kafka handle")
	return K.rd_kafka_poll(self._rk, timeout_ms or 0)
end

-- Allocates a topic handle.
-- :: string -> Topic
function Producer:topic(name)
	assert(self._rk, "bad kafka handle")
	local rkt = K.rd_kafka_topic_new(self._rk, name, nil)
	assert(rkt, "fail to make a topic handle")
	ffi.gc(rkt, K.rd_kafka_topic_destroy)
	return rkt
end

-- :: Topic, string, string? -> boolean
function Producer:produce(topic, payload, key)
	assert(self._rk, "bad kafka handle")
	assert(topic, "bad topic handle")
	local err = K.rd_kafka_produce(
		topic, K.RD_KAFKA_PARTITION_UA, K.RD_KAFKA_MSG_F_COPY,
		ffi.cast("void*", payload), #payload,
		ffi.cast("void*", key), #(key or ""),
		nil)
	return err == 0
end

return {Config = Config, Producer = Producer}
