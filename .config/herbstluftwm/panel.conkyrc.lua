local lfs = require "lfs"

function conky_init()
    if trim(readfile("/home/felix/.colors")) == "dark" then
        s = { -- dark
            bgcolor      = "121212",
            fgcolor      = "EFEFEF",
            fgcolorinact = "444444",
            fgcolordim   = "909090",
            fgcolorbad   = "FF3F74",
            bgcolorsel   = "37BAFF",
            fgcolorsel   = "000000",
            bgcolorurgent= "CE6D00",
            charwidth    = 8
        }
    else
        s = { -- light
            bgcolor      = "FFFFFF",
            fgcolor      = "000000",
            fgcolorinact = "AAAAAA",
            fgcolordim   = "888888",
            fgcolorbad   = "FF3F74",
            bgcolorsel   = "00D7FF",
            fgcolorsel   = "000000",
            bgcolorurgent= "FFD8AC",
            charwidth    = 9
        }
    end
    s.cpucount = exec("grep 'physical id' /proc/cpuinfo | wc -l")
    -- s.cpucount = 1
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

function scroll(content, commandup, commanddown)
    return "^ca(4,"..commandup..")^ca(5,"..commanddown..")"..content.."^ca()^ca()"
end

function click(content, command)
    return "^ca(1,"..command..")"..content.."^ca()"
end

function icon(name)
    -- return " ^p(-"..s.charwidth..")^i(/usr/share/icons/stlarch_icons/"..name..")"
    return ""
end

function conky_sep()
    return bg(s.bgcolor)..fg(s.bgcolorsel).." ^p(-1)^r(1x16) "
end

function conky_prefix(prefix)
    return fg(s.fgcolordim)..prefix..fg(s.fgcolor)
end

function conky_hctitle()
    local title = trim(hc("attr clients.focus.title"))
    title = title:gsub("%$","$$")
    return fg(s.fgcolor)..title
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
        elseif  tagstatus == "!" then addtag(tagname, s.bgcolorurgent, s.fgcolorsel)
        else                          addtag(tagname, s.bgcolor, s.fgcolorinact) end

    end
    return tags .. bg(s.bgcolor)
end

function conky_cpu(height)
    local str = conky_prefix("cpu ")
    -- bar for each cpu
    for cpu = 0,(s.cpucount-1) do
        local cpuload = conky("cpu cpu"..cpu.."")
        str = str .. conky_vbar(cpuload, 100, height)
    end
    return str
end

function conky_mem(height)
    local swapperc = tonumber(conky("swapperc"))
    local str = conky_prefix("mem ")
    str = str..conky_vbar(conky("memperc"),100, height)

    if(swapperc ~= nil and swapperc > 0) then
        str = str ..fg(s.fgcolorbad)..conky_vbar(conky("swapperc"),100, height)
    end

    return str
end

function conky_bat(height)
    local col = fg(s.fgcolor)
    local batpc = conky("battery_percent")
    if(batpc ~= nil and tonumber(batpc) <= 10) then
        col = fg(s.fgcolorbad)
    end
    return conky_prefix("bat ")..col..conky_vbar(conky("battery_percent"),100, height)..conky_format("%11s", conky("battery_time"))

end

function conky_net(height)
    function iface_speed(iface)
        return " "..conky_format("%7s", trim(conky("upspeedf "..iface))).."K up"..icon("uparrow3.xbm")
        .." "..conky_format("%7s", trim(conky("downspeedf "..iface))).."K down"..icon("downarrow3.xbm")
        ..conky_sep()
    end

    local str = ""
    for i,iface in pairs(files("/sys/class/net")) do
        if iface ~= "lo" then
            local essid = conky("wireless_essid "..iface)
            if( essid == nil or essid == "" ) then -- ethernet device
                str = str ..conky_prefix(iface).. iface_speed(iface)
            else -- wifi device
                if( essid ~= "off/any" ) then
                    -- local qual = tonumber(conky("wireless_link_qual_perc " .. iface))

                    -- if     qual <= 33 then str = str .. conky_prefix(icon("wireless10.xbm"))
                    -- elseif qual <= 66 then str = str .. conky_prefix(icon("wireless9.xbm"))
                    -- else                   str = str .. conky_prefix(icon("wireless8.xbm")) end

                    str = str..conky_prefix(iface).." "..conky_vbar(conky("wireless_link_qual_perc "..iface), 100, height) .. " ".. essid .. iface_speed(iface)
                end
            end
        end
    end
    return click(str, "nmcli_dmenu")
end

function conky_vol(height)
    local vol = tonumber(exec("pacmd list-sinks | grep front-left | grep -Eo \"[0-9]{1,3}%\" | head -1 | cut -d \"%\" -f 1"))
    if trim(exec("pacmd list-sinks | grep \"muted: \" | cut -d \":\" -f 2")) == "yes" then
        vol = "m"
    else
        -- vol = conky_format("%3s", vol)
        vol = conky_vbar(vol, 100, height)
    end
    return scroll(click(conky_prefix("vol"),"pavucontrol").." "..click(vol,
            "pulseaudio-ctl mute; herbstclient emit_hook panel_refresh"),
        "pulseaudio-ctl up;   herbstclient emit_hook panel_refresh",
        "pulseaudio-ctl down; herbstclient emit_hook panel_refresh")
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

function readfile(filename)
    local file = io.open(filename, "rb")
    local content = file:read("*all")
    file:close()
    return content
end

function hc(command)
    return exec("herbstclient "..command.." 2> /dev/null")
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
