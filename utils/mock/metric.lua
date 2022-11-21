---------------------------------------------------
local metric = {}
---------------------------------------------------

function metric.add_int_counter(name, value)
    __mock.trace("__metric.add_int_counter", name, value)
end

function metric.add_int_gauge_counter(name, value)
    __mock.trace("__metric.add_int_gauge_counter", name, value)
end

function metric.add_int_updown_counter(name, value)
    __mock.trace("__metric.add_int_updown_counter", name, value)
end

function metric.add_int_histogram(name, value)
    __mock.trace("__metric.add_int_histogram", name, value)
end

function metric.add_float_counter(name, value)
    __mock.trace("__metric.add_float_counter", name, value)
end

function metric.add_float_gauge_counter(name, value)
    __mock.trace("__metric.add_float_gauge_counter", name, value)
end

function metric.add_float_updown_counter(name, value)
    __mock.trace("__metric.add_float_updown_counter", name, value)
end

function metric.add_float_histogram(name, value)
    __mock.trace("__metric.add_float_histogram", name, value)
end

return metric
