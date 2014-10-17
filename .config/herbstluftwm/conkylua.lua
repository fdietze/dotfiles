function conky_format( format, number )
    return string.format( format, conky_parse( number ) )
end

function conky_cpubar( cpunum )
    load = tonumber(conky_parse("${cpu cpu" .. cpunum .. "}"))
    if load == nil then load = 0 end
    maxh = 16
    height = math.max(math.floor(load*maxh/100),1)
    return "^p(;"..(maxh-height+1)..")^r(5x"..height..")^p()"
end
