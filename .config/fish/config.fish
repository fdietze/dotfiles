# parse .profile
egrep "^export " ~/.profile | while read e
	set var (echo $e | sed -E "s/^export ([A-Z_]+)=(.*)\$/\1/")
	set value (echo $e | sed -E "s/^export ([A-Z_]+)=(.*)\$/\2/")
	
	# remove surrounding quotes if existing
	set value (echo $value | sed -E "s/^\"(.*)\"\$/\1/")

	if test $var = "PATH"
		# replace ":" by spaces. this is how PATH looks for Fish
		set value (echo $value | sed -E "s/:/ /g")
	
		# use eval because we need to expand the value
		eval set -xg $var $value

		continue
	end

	# evaluate variables. we can use eval because we most likely just used "$var"
	set value (eval echo $value)

	#echo "set -xg '$var' '$value' (via '$e')"
	set -xg $var $value
end


set fish_greeting ""


source ~/.sh_aliases

# activate z
. ~/bin/z.fish

# colorize a huge set of commands
set -x PATH (cope_path) $PATH

# activate colorful file listings
eval "set -x LS_COLORS" (dircolors ~/.dir_colors | grep -P "'.*'" -o)

# colorize manpages
set -x LESS_TERMCAP_mb (printf "\33[01;34m") # begin blinking
set -x LESS_TERMCAP_md (printf "\33[01;34m") # begin bold
set -x LESS_TERMCAP_me (printf "\33[0m")     # end mode
set -x LESS_TERMCAP_se (printf "\33[0m")     # end standout-mode
set -x LESS_TERMCAP_so (printf "\33[44;1;37m") # begin standout-mode - info box
set -x LESS_TERMCAP_ue (printf "\33[0m")     # end underline
set -x LESS_TERMCAP_us (printf "\33[01;35m") # begin underline

# start X at login
if status --is-login
    if test -z "$DISPLAY" -a $XDG_VTNR = 1
        # exec startx
    end
end
