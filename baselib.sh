#!/bin/sh

# test from repo itself

PATH="$PATH:/opt/bin:/usr/local/sbin"

# Put in a variable main script arguments
m=0
declare -a mainArgs
if [ ! "$#" = "0" ]; then
	for arg in "$@"; do
		mainArgs[$m]=$arg
		m=$(($m + 1))
	done
fi

function isProgramExist() 
# $1 Program to test
{
	local progToTest=$1
	command -v $progToTest >/dev/null 2>&1 || { echo >&2 "I require $progToTest but it's not installed.  Aborting."; exit 1; }
}

function activateLogs() {
	local isFileDescriptor3Exist=$(command 2>/dev/null >&3 && echo "Y")
	
	if [ "$isFileDescriptor3Exist" = "Y" ]; then
		echo "Logs are configured"
	elif [ ! -t 1 ] || [ ! -t 2 ]; then
		echo "Logs are configured externally"
	else
		local logPath="logs"
		if [ ! -d $logPath ]; then mkdir $logPath; fi
		
		local logFileName=$(basename "$0")"."$(date +%Y-%m-%d.%k-%M-%S)
	
		# FROM: https://stackoverflow.com/a/45426547/214898
		exec 3<> "$logPath/$logFileName.log"
		"$0" "${mainArgs[@]}" 2>&1 1>&3 | tee -a "$logPath/$logFileName.err" 1>&3 &
		exit
	fi
}

function launchOnlyOnce() {
	local scriptDir=$(dirname "$0")
	local bashFile=$(echo "$0" | awk -F "/" '{print $NF}')
	local fullProgramLine="$SHELL $scriptDir/$bashFile"
	
	launchScriptWithFullPath

	# Try "ps" command with options or without if not working
	local instances
	instances=$(ps -aux 2>/dev/null) # Can not be with "local declaration" because otherwise the exit code is the one of LOCAL and not PS
	local exitCode=$?
	local nbOneInstance=2 # One for itself + one for grep # FIXME: It was 3 before, but tested on Ubuntu which has (ps -aux) and it is still 2
	if [ $exitCode -ne 0 ]; then
		instances=$(ps 2>/dev/null)
	fi
	
	# Shall gives $nbOneInstance for a single instance
	local nbInstances=$(echo "$instances" | grep -F "$fullProgramLine" | wc -l)
	
	if [ $nbInstances -gt $nbOneInstance ]; then
		echo "Script \"$scriptDir/$bashFile\" already running"
		exit
	fi
}

function launchScriptWithFullPath() {
	local relaunched=$(
		setDirToScriptOne
		
		scriptDir=$(dirname "$0")
		curDir=$(pwd)
		bashFile=$(echo "$0" | awk -F "/" '{print $NF}')
		
		if [ ! "$scriptDir" = "$curDir" ]; then
			echo "$curDir/$bashFile"
		else
			echo ""
		fi
	)
	
	if [ ! "$relaunched" = "" ]; then
		exec "$relaunched" "${mainArgs[@]}" &
		exit
	fi
}

function setDirToScriptOne() {
	local scriptDir=$(dirname "$0")
	cd "$scriptDir"
}

function escapeForRegEx() 
# $1=$stringToEscape

#From: https://www.linuxquestions.org/questions/programming-9/passing-variables-which-contain-special-characters-to-sed-4175412508/
{
	# start with the original pattern
	local escaped="$1"

	# escape all backslashes first
	escaped="${escaped//\\/\\\\}"

	# escape slashes
	escaped="${escaped//\//\\/}"

	# escape asterisks
	escaped="${escaped//\*/\\*}"
	
	# escape ampersand
	escaped="${escaped//\&/\\&}"

	# escape full stops
	escaped="${escaped//./\\.}"    

	# escape [ and ]
	escaped="${escaped//\[/\\[}"
	escaped="${escaped//\]/\\]}"

	# escape ^ and $
	escaped="${escaped//^/\\^}"
	escaped="${escaped//\$/\\\$}"
	
	echo $escaped
}


function show_progress()
# $1 = $current
# $2 = $max
{
	local curLine=$1
	local nbDiffLines=$2
	local percent=$(($curLine*100))
	percent=$(($percent/$nbDiffLines))

	local curP=1
	local percentLine=""
	local percentByTen=$(($percent/10))
	while [ $curP -le $percentByTen ]; do
		percentLine="$percentLine#"
		curP=$(($curP+1))
	done
	
	while [ $percentByTen -le 10 ]; do
		percentLine="$percentLine "
		percentByTen=$(($percentByTen+1))
	done
	
	echo -ne "$percentLine ($percent%)\\r"
}

function send_mail()
#   Send a mail message
#   $1 = subject
#   $2 = to
#   $3 = from
#   $4 = msg
{
   local tmpfile="/tmp/$(basename $0).$$.tmp"
   /bin/echo -e "Subject: $1\r" > "$tmpfile"
   /bin/echo -e "To: $2\r" >> "$tmpfile"
   /bin/echo -e "From: $3\r" >> "$tmpfile"
   /bin/echo -e "\r" >> "$tmpfile"
   if [ -f "$4" ]; then
      cat "$4" >> "$tmpfile"
      /bin/echo -e "\r\n" >> "$tmpfile"
   else
      /bin/echo -e "$4\r\n" >> "$tmpfile"
   fi
   /usr/sbin/sendmail -t < "$tmpfile"
   rm $tmpfile
}