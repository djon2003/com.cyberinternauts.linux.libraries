#!/bin/sh

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
	command -v $progToTest >/dev/null 2>&1 || { echo "N"; return; }
	echo "Y";
}

function ensureProgramExist() 
# $1 Program to test
{
	local progToTest=$1
	local isExisting=$(isProgramExist "$progToTest")
	if [ ! "$isExisting" = "Y" ]; then
		echo >&2 "I require $progToTest but it's not installed.  Aborting."; exit 1;
	fi
}

function hasMainArg()
# $1 string to find
{
	local match="$1"
	containsElement "$1" "${mainArgs[@]}"
	return $?
}

function containsElement()
# $1 string to find
# $2 array to search in
{
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

function executeAndFilterErrors()
# $1 array of filters: Have to be declared outside also with the same name
# $2 command to execute. If using double quote, they shall be espaced with a backslash
# Usage example: 
#   errorsToFilter=("@Recy cle" "@Recycle" "three")
#   executeAndFilterErrors "${errorsToFilter[@]}" ls -lLAsR \"$path\"
{
	local -n errorsToFilter=$1 2>/dev/null; # Do work even though there is an error, so forget it.
	for i in "${errorsToFilter[@]}"
	do : 
		shift
	done
	
	local command=$@
	printf '%s\n' "${command[@]}"
	(
		exec 10>&1 #set up extra file descriptors

		error=$( { eval "${command[@]}" 1>&10; } 2>&1 )
		for i in "${errorsToFilter[@]}"
		do : 
			filter=$(escapeForRegEx "$i")
			error=$(echo "$error" | sed "s/^.*$filter.*$//")
		done
		error=$(echo "$error" | sed "/^[[:space:]]*$/d")

		exec 10>&-

		if [[ "$error" != "" ]]; then
			>&2 echo "$error"
		fi
	)
}

function activateLogs()
# $1 = logOutput: What is the output for logs: SCREEN, DISK, BOTH. Default is DISK. Optional parameter.
{
	local logOutput=$1
	if [ "$logOutput" != "SCREEN" ] && [ "$logOutput" != "BOTH" ]; then
		logOutput="DISK"
	fi
	
	if [ "$logOutput" = "SCREEN" ]; then
		echo "Logs will only be output to screen"
		return
	fi
	
	hasMainArg "--force-log"
	local forceLog=$?
		
	local isFileDescriptor3Exist=$(command 2>/dev/null >&3 && echo "Y")
	
	if [ "$isFileDescriptor3Exist" = "Y" ]; then
		echo "Logs are configured"
	elif [ "$forceLog" = "1" ] && ([ ! -t 1 ] || [ ! -t 2 ]); then
		# Use external file descriptor if they are set except if having "--force-log"
		echo "Logs are configured externally"
	else
		echo "Relaunching with logs files"
		local logPath="logs"
		if [ ! -d $logPath ]; then mkdir $logPath; fi
		
		local logFileName=$(basename "$0")"."$(date +%Y-%m-%d.%k-%M-%S)
	
		if [ "$logOutput" = "DISK" ]; then
			# FROM: https://stackoverflow.com/a/45426547/214898
			exec 3<> "$logPath/$logFileName.log"
			"$0" "${mainArgs[@]}" 2>&1 1>&3 | tee -a "$logPath/$logFileName.err" 1>&3 &
		else
			# FROM: https://stackoverflow.com/a/70790574/214898
			exec 3>&1
			{ "$0" "${mainArgs[@]}" | tee -a "$logPath/$logFileName.log" & } 2>&1 1>&3 | tee -a "$logPath/$logFileName.err" &
		fi
		
		exit		
	fi
}

function launchOnlyOnce()
{
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

function launchScriptWithFullPath()
{
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

function setDirToScriptOne()
{
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


function showProgress()
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

function renameFunction()
# $1 = current function name
# $2 = new function name
# FROM: https://mharrison.org/post/bashfunctionoverride/
{
    local ORIG_FUNC=$(declare -f $1)
    local NEWNAME_FUNC="$2${ORIG_FUNC#$1}"
	unset -f $1 2>/dev/null
	if [ $? -eq 0 ]; then
		eval "$NEWNAME_FUNC"
	fi
	
	return $?
}

function sendMail()
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
