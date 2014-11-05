local lfs = require "lfs"

function conky_init()
    if trim(readfile("/home/felix/.colors")) == "dark" then
        s = {
            bgcolor      = "121212",
            fgcolor      = "EFEFEF",
            fgcolorinact = "444444",
            fgcolordim   = "909090",
            fgcolorbad   = "FF3F74",
            bgcolorsel   = "37BAFF",
            fgcolorsel   = "000000",
            charwidth    = 8
        }
    else
        s = {
            bgcolor      = "FFFFFF",
            fgcolor      = "000000",
            fgcolorinact = "AAAAAA",
            fgcolordim   = "888888",
            fgcolorbad   = "FF3F74",
            bgcolorsel   = "00D7FF",
            fgcolorsel   = "000000",
            charwidth    = 8
        }
    end
end

function conky(var)
    return conky_parse("${"..var.."}")
end


function fg(c)
    return "^fg(\\#"..c..")"

end

function bg(c)
    return "^bg(\\#"..c..")"

end

function click(content, command)
    return "^ca(1,"..command..")"..content.."^ca()"
end

function icon(name)
    return " ^p(-"..s.charwidth..")^i(/usr/share/icons/stlarch_icons/"..name..")"
end

function conky_sep()
    return bg(s.bgcolor)..fg(s.bgcolorsel).." ^p(-1)^r(1x16) "
end

function conky_prefix(prefix)
    return fg(s.fgcolordim)..prefix..fg(s.fgcolor)
end

function conky_hctitle()
    return fg(s.fgcolor)..trim(hc("attr clients.focus.title"))
end

function conky_hctags()
    local tags = ""
    function addtag(tagname, bgc, fgc)
        tags = tags.. bg(bgc)..fg(fgc)..click(" "..tagname.." ", "herbstclient use ".. tagname)
    end

    for tag in string.gmatch(hc("tag_status"),".%d+") do
        local tagname = string.sub(tag, 2)
        local tagstatus = string.sub(tag, 0, 1)

        if      tagstatus == ":" then addtag(tagname, s.bgcolor, s.fgcolor)
        elseif  tagstatus == "#" then addtag(tagname, s.bgcolorsel, s.fgcolorsel)
        else                          addtag(tagname, s.bgcolor, s.fgcolorinact) end

    end
    return tags
end

function conky_cpu(cpucount, height)
    local str = conky_prefix("cpu ")
    -- bar for each cpu
    for cpu = 0,(cpucount-1) do
        local cpuload = conky("cpu cpu"..cpu.."")
        str = str .. conky_vbar(cpuload, 100, height)
    end
    return str
end

function conky_mem()
    return conky_prefix("mem ")..conky_format("%7s", conky("memeasyfree"))
end

function conky_bat()
    local col = fg(s.fgcolor)
    local batpc = conky("battery_percent")
    if(batpc ~= nil and tonumber(batpc) <= 10) then
        col = fg(s.fgcolorbad)
    end
    return conky_prefix("bat ")..col..conky_format("%11s", conky("battery_time"))
end

function conky_net()
    function iface_speed(iface)
        return " "..conky_format("%7s", trim(conky("upspeedf "..iface))).."K"..icon("uparrow3.xbm")
        .." "..conky_format("%7s", trim(conky("downspeedf "..iface))).."K"..icon("downarrow3.xbm")
        ..conky_sep()
    end

    local str = ""
    for i,iface in pairs(files("/sys/class/net")) do
        if iface ~= "lo" then
            local essid = conky("wireless_essid "..iface)
            if( essid == nil or essid == "" ) then -- ethernet device
                str = str .. conky_prefix("eth ") .. iface_speed(iface)
            else -- wifi device
                if( essid ~= "off/any" ) then 
                    local qual = tonumber(conky("wireless_link_qual_perc " .. iface))
                    
                    if     qual <= 33 then str = str .. conky_prefix(icon("wireless10.xbm"))
                    elseif qual <= 66 then str = str .. conky_prefix(icon("wireless9.xbm"))
                    else                   str = str .. conky_prefix(icon("wireless8.xbm")) end

                    str = str .. " ".. essid .. iface_speed(iface)
                end
            end
        end
    end
    return str
end

function conky_date()
    return conky_prefix(conky("time %Y-%m-%d")).." "..conky("time %H:%M")
end

function conky_vbar(value, max, height)
    value = tonumber(value)
    if value == nil then value = 0 end
    local amplitude = math.max(math.floor(value*height/max),1)
    return " ^p(-"..s.charwidth..")^p(;"..(height-amplitude+1)..")^r("..(s.charwidth-1).."x"..amplitude..")^p(1)^p()"
end

function exec(command)
    local file = io.popen(command)
    local output = file:read('*all')
    file:close()
    return output
end

function hc(command)
    return exec("herbstclient "..command)
end

function trim(s)
  return s:match'^%s*(.*%S)' or ''
end

function conky_format( format, number )
    return string.format( format, conky_parse( number ) )
end

function files(dir)
    local filelist = {}
    for file in lfs.dir(dir) do
        if file ~= "." and file ~= ".." then
            table.insert(filelist, file)
        end
    end
    return filelist
end
