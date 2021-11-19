#!/bin/bash
#
# Copyright (C) 2020-2021 Lucas Vinícius Guedes da Silva
#
# command to automate package instalation from slackbuilds.com 

# url="https://slackbuilds.org/reinditory/14.2/desktop/plank/?search=plank"

# exit immediately if some error occurs
set -e

# **You must 'declare -a URL_ARR' before calling this function
# Usage: ParseUrl <url>
# Return: Void
# Side effect: fullfills the declared array named URL_ARR
# {{{
function ParseUrl {
  local url="${1}"
  local BASE_URL="$(echo "${url}" | grep -o 'https://[^/]\+')"
  local subUrl="$(echo "${url}" | sed -e 's/https:\/\/[^/]\+//')"
  local urlStr="${url} ${BASE_URL} ${subUrl}"
  local ind=0

  #empting the array
  if [ -n "${URL_ARR[*]}" ]; then
    unset URL_ARR
    declare -g -a URL_ARR
  fi

  #fullfilling the array
  for url in $urlStr
  do
    URL_ARR[$ind]="$url"
    ind=$(($ind + 1))
  done
}
#}}}

# Usage: GetName <url>
# Return: "packageName"
# {{{
function GetName {
  local url="${1}"
  local package
  if echo "${url}" | grep '?search' 1> /dev/null || \
     echo "${url}" | grep '.*/$'    1> /dev/null
  then
    # echo "There is search"
    package=${url%/*}
    package=${package##*/}
  else
    # echo "The new url is local but I can access here: ${package}"
    # echo "No search found"
    package=${url##*/}
  fi
  echo "$package"
}
# }}}

# Usage: HasDepsTo <url>
# Return: "true" or "false"
# {{{
function HasDepsTo {
  local url="${1}"

  if wget --no-check-certificate \
	  -qO /dev/stdout "${url}" \
	  | grep 'This requires:'  1>  /dev/null
  then
    echo true
  else
    echo false
  fi
}
# }}}


# Usage: GetDepsStr <url>
# Returns a list of the URLs to be
# added to the baseURL of each package:
# "/parc/url/package1 /parc/url/package2 /parc/url/package3"
# {{{
function GetDepsStr {
    wget --no-check-certificate \
	 -qO /dev/stdout "${1}" \
    | grep 'This requires:' \
    | grep -o "'[^'<>=]\\+'" \
    | tr "\n" " " \
    | tr -d "'"
}
# }}}
 

# **You must 'declare -a DEPS_ARR' before calling this function
# Usage: GetDeps<url>
# <url> is a string
# Return: void
# Side effect: fullfills the global declared DEPS_ARR array
# {{{
function GetDeps {
  local url="${1}"
  local depsStr=$(GetDepsStr "$url")
  
  if [ "$(HasDepsTo "${URL_ARR[0]}")" = "true" ]
    then
    # empting 
    if [ -n "${DEPS_ARR[*]}" ]
    then
      unset DEPS_ARR
      declare -g -a DEPS_ARR
    fi

    # fullfilling
    local ind=0
    for dep in ${depsStr}
    do
      DEPS_ARR[$ind]="${dep}"
      ind=$(($ind + 1))
    done
  else
    echo "No deps to: ${URL_ARR[0]}"
    unset DEPS_ARR
  fi
}
# }}}

# Usage: InsertPackage <level>
#   <level> is an integer
# Return: void
# Side effect: Insert a new entry in DEP_TREE
# ** This function makes use of the following 
#    global variables:
#      URL_ARR  , must be fullfilled
#      DEPS_ARR , must be fullfilled
#      DEP_TREE , can be void
# {{{
function InsertPackage {
  local level=${1}
  local name=$(GetName "${URL_ARR[0]}")
  local nameExists 

  #if the array is not void, search it
  if ! [ ${#DEP_TREE[@]} -eq 0 ]; then
    #searching the array DEP_TREE if the name already exists
    for ((m=0; m < ${#DEP_TREE[@]}; m++))
    do
      if echo "${DEP_TREE[$m]}" | grep "[0-9]\+ $name " &> /dev/null; then
        nameExists="true"
        break
      fi
    done
  fi

  # if the name exists don't add it again
  if [ "$nameExists" != "true" ]; then
    DEP_TREE[$INDEX]=$LEVEL
    DEP_TREE[$INDEX]+=" $name"
    DEP_TREE[$INDEX]+=" ${URL_ARR[*]}"
    DEP_TREE[$INDEX]+=" ${DEPS_ARR[*]}"


    # DEBUG MESSAGE: Print inserted entry
    if [ "$DEBUG_MODE" = "on" ]; then
      echo
      echo Entry successfully inserted:
      echo "${DEP_TREE[$INDEX]}"
      echo "If the entry doesn't appear see the variables:"
      echo "level = ${level}"
      echo "INDEX = ${INDEX}"
      echo "ind = ${ind}"
      sleep 2
    fi


    INDEX=$(($INDEX + 1))
  fi
}
# }}}

# Function: NumPacks
# This function analyzes each entry of
# the DEP_TREE array at a given level
# and return the total sum of the
# packages found at that level
# {{{
function NumPacks {
  local level="$1"
  local totalPacks=0


  for ((i = 0; i < ${#DEP_TREE[@]}; i++))
  do
    if echo "${DEP_TREE[$i]}" | grep "^${level} " > /dev/null
    then
      totalPacks=$(($totalPacks + 1))
    fi
  done

  echo "$totalPacks"
}
# }}}

# Function: GetDepsList
# This function analyzes each entry of
# the DEP_TREE array at a given level
# and catches all deps of each entry at 
# that level. Finally it merges them all 
# in a single list that is returned 
# {{{
function GetDepsList {
  local level="$1"  
  local depList=""
  local entry

  for ((i = 0; i < ${#DEP_TREE[@]}; i++))
  do
    entry="${DEP_TREE[$i]}"

    if echo "$entry" | grep "^${level} " &> /dev/null
    then

      # leaving only the [depsList] part of
      # the entry string
      entry="$(TreeElem $i 5)"

      if [ -z "$depList" ]
      then
        depList+="${entry}"
      else 
        # processing each dependency of the entry string
        for dep in $entry; do
          if ! echo "$depList" | grep "$dep" &> /dev/null; then
            depList+=" ${dep}"
          fi
        done
      fi

    fi

  done

  echo "${depList}"
}
# }}}

# Function: LevelInsert
# Insert packages by level in the dependency tree
# {{{
function LevelInsert {
  local nPacks
  local depsUrlList
 # declare -a depsUrl


  while [ 1 ]; do
    declare -a depsUrl
    echo
    echo "------------- Level: $LEVEL ----------------"
    echo
    if [ $LEVEL -eq 0 ]
    then
      InsertPackage ${LEVEL}
    else
      # analyze the last level:

      #  - how many packages last level had?
      nPacks=$(NumPacks $(($LEVEL - 1)))
      echo "Number of packs of last level: $nPacks"


      #  - what are the deps of each of them?
      depsUrlList=$(GetDepsList $(($LEVEL - 1)))
      # if the list is zero-length then break
      # no more deps in the last level to create this new one
      if [ -z "${depsUrlList}" ]; then
        echo -e "\n\ndepsUrlList is VOID!!!!!!!!!\n\n"
        echo "Exiting now"
        break 
      else
        echo -e "\ndepsUrlList = $(echo ${depsUrlList} | tr ' ' '\n')"
      fi

      # mounting the full URL to each of the depsUrlList
      # and assigning it to the local array depsUrl
      local ind=0
      for depSubUrl in $depsUrlList
      do
        depsUrl[$ind]="${BASE_URL}${depSubUrl}"
        ind=$(($ind + 1))
      done
      if [ "$DEBUG_MODE" = "on" ]; then
        echo
        echo "depsUrl[@] = ${depsUrl[@]}"
        echo "depsUrl[0] = ${depsUrl[0]}"
        echo "#depsUrl[@] = ${#depsUrl[@]}"
      fi


      #  the deps of them will be inserted as packs in this level
      local ind=0
      while [ $ind -lt ${#depsUrl[@]} ]
      do
        ParseUrl "${depsUrl[$ind]}"
        GetDeps "${URL_ARR[0]}"
        InsertPackage ${LEVEL} 
        ind=$(($ind + 1))
      done

    fi
    LEVEL=$(($LEVEL + 1))
    unset depsUrl
  done

    #  repeat until a level whose packages from the last level
    #  don't have deps is reached
}
# }}}

# Function: PrintDepTree
# {{{
function PrintDepTree {
  local nZeros=$[ $[ $((${#DEP_TREE[@]}-1)) / 10 ] + 1 ]
  echo
  echo "Dependencies: "
  for ((i = 0; i < ${#DEP_TREE[@]}; i++))
  do
    printf "%${nZeros}d) %s\n\n" $i "${DEP_TREE[$i]}"
  done
}
# }}}


# Usage: MoveLine <fromInd> <toInd>
# <fromInd> is integer
# <toInd> is integer
# Side effect: change array DEP_TREE (global)
# Return: void
# {{{
function MoveLine {
  local fromInd=$1
  local toInd=$2
  local tempVar

  tempVar="${DEP_TREE[$fromInd]}"

  if [ $fromInd -lt $toInd ]; then

    local ind=$fromInd

    while [ $ind -le $toInd ]; do
      #local nextInd=$(($ind + 1))
      DEP_TREE[$ind]="${DEP_TREE[$(($ind + 1))]}"
      ind=$(($ind + 1))
    done

  elif [ $fromInd -gt $toInd ]; then

    local ind=$fromInd

    while [ $ind -gt $toInd ]; do
      DEP_TREE[$ind]="${DEP_TREE[$(($ind - 1))]}"
      ind=$(($ind - 1))
    done

  fi
  DEP_TREE[$toInd]="$tempVar"
}
# }}}

# Function: TreeElem
# Description: DEP_TREE is a single dimension array but if we 
# put strings in it the list items can become a second 
# dimension that can be accessed with this function
#
# Usage: TreeElem <line> <column>
#  - <line> is integer
#  - <column> is integer
# Return the list item in the index of DEP_TREE where:
#         0          1     2         3        4          5
#   [level] [packName] [url] [BASE_URL] [subUrl] [depsList]
# {{{
function TreeElem {
  local lin=$1
  local col=$2
  local item
  local numCols=-1

  if [ -n "$col" ]
  then
    if [ $col -eq 0 ]; then
      item="${DEP_TREE[$lin]%% *}"
    elif [ $col -lt 5 ]; then
      item="${DEP_TREE[$lin]}"
      for ((i = 0; i < $col; i++)); do
        item="${item#* }"
      done
      item="${item%% *}"
    else
      # counting the existing number of columns
      for colItem in ${DEP_TREE[$lin]}; do
        numCols=$(($numCols + 1))
      done
      if [ $numCols -lt $col ]; then
        # the number given by col does not exist in line
        item=""
      else
        item="${DEP_TREE[$lin]}"
        for ((i = 0; i < $col; i++)); do
          item="${item#* }"
        done
      fi
    fi
  else
    item="${DEP_TREE[$lin]}"
  fi

  echo "$item"
}
# }}}


# Usage: ChangeLine <line> <column> <newValue>
# Return: void
# Side-effect: change <column> from <line> in DEP_TREE
# {{{
function ChangeLine {
  local line=$1 
  local column=$2
  local newValue="$3"
  local colNumber=0
  local newLine
  # even the for aux variables must be declared as 
  # local here otherwise they will be treated as global
  local i
  declare -a colArr

  # 1 - get the <line> from DEP_TREE and convert the list in an array representing columns
  for col in ${DEP_TREE[$line]}; do
    if [ $colNumber -lt 5 ]; then
      colArr[$colNumber]="$col"
      colNumber=$(($colNumber + 1))
    else
      if [ -z "${colArr[$colNumber]}" ]; then
        colArr[$colNumber]="$col"
      else
        colArr[$colNumber]+=" $col"
      fi
    fi
  done

  # 2 - substitute <newValue> in <column> index 
  colArr[$column]="$newValue"

#  echo -e "\n\n\nChangeLine (outside for) i = $i"
#  read -p "press something to continue..." trash
  # 3 - put the concatenation of columns array as string in line of DEP_TREE
  for ((i=0; i < ${#colArr[@]}; i++)); do
    # using k as variable is necessary, i generates conflict with Rearrange
    # or you can declare i as local with variables as done above
#    echo -e "\n\n\nChangeLine (inside for) k = $k"
#    read -p "press something to continue..." trash
    if [ -z "$newLine" ]; then
      newLine="${colArr[$i]}"
    else
      newLine+=" ${colArr[$i]}"
    fi
  done
#  echo -e "\ncolArr[@] = ${colArr[@]}"

  DEP_TREE[$line]="$newLine"
}
# }}}


# Usage: Rearrange
# Return: void
# Side-effect: Change the array DEP_TREE (global)
# {{{
function Rearrange {
  # 1 - find a line without deps
  local i=$((${#DEP_TREE[@]} - 1))
  while [ $i -gt 0 ]; do
    if [ -z "$(TreeElem $(($i - 1)) 5)" ]; then
      # 2 - move it to the last line $((${#DEP_TREE[@]} - 1))
      MoveLine $(($i - 1)) $((${#DEP_TREE[@]} - 1)) 
      # 3 - change the [level] column to the last level which is represented by level global var
#      echo -e "\nLEVEL = $LEVEL"
#      read -p "press something to continue..." trash
      ChangeLine $((${#DEP_TREE[@]} - 1)) 0 $LEVEL
    fi
    i=$(($i - 1))
#    echo -e "\nRearrange (local var) i = $i"
#    read -p "press something to continue..." trash
  done
  # 4 - repeat this process to each line of DEP_TREE array
}
# }}}


# --------------- INSTALL FUNCTIONS ----------------------------
# Usage: GetLinks <searchStr> <url>
# <searchStr> is String
# <url> is String
# Return: A string list with the download links
# Side-effect: none
# {{{
function GetLinks {
  local searchStr="$1"  # "Source Downloads" or "Download SlackBuild"
  local url="$2"
  
  if echo "$searchStr" | grep -i "source" &> /dev/null
  then
    #wget -qO- "$url" \
    curl -k "$url" \
      | grep -A 10 "$searchStr" \
      | grep -o "href=\".\+\"" \
      | sed 's/href=//g' \
      | tr -d '"' \
      | sed 's|^/.\+$||g' \
      | tr  '\n' ' '
  else
    #wget -qO- "$url" \
    curl -k "$url" \
      | grep "$searchStr" \
      | grep -o "href=\".\+\"" \
      | sed 's/href=//g' \
      | tr -d '"' 
  fi
}
# }}}

# Usage: DwdFile <url> <outDir>
# <url> is String
# <outDir> is String ("." current dir by default)
# Return: void
# Side-effect: download file in <url> inside <outDir>
# {{{
function DwdFile {
  local fileLink="$1"
  local outDir="${2:-.}"  # It's the prefix
  local BASE_URL="https://slackbuilds.org"

  # Complete the url with BASE_URL if the url starts with "/"
  if echo $fileLink | grep "^/.\+$" &> /dev/null; then
    fileLink="$BASE_URL${fileLink% }"  # remove the final space
    #read -p "Check the variable value fileLink=\"${fileLink}\"" fooBar
  fi
  
  wget --no-check-certificate -P "$outDir" "$fileLink"
}
# }}}


# Usage: Install <url>
# <url> is String
# Return: void
# Side-effect: that known routine to install a SlackBuild
# {{{
function Install {
  local url="$1"
  echo -e "\n\n------------- INSTALLATION ------------------------"
  echo -e "The passed URL is:\n\t $1"

  echo -e "\nGetting the sources download links"
  local srcLinks="$(GetLinks "Source Downloads" "$url")"
  echo -e "The src links are:\n$(echo "$srcLinks" | tr ' ' "\n")"

  echo -e "\nGetting the slack build download link"
  local sbLink="$(GetLinks "Download SlackBuild" "$url")"
  echo -e "The slackbuild link is:\n\t$sbLink"

  local fileName=${sbLink##*/}
  echo -e "\nDownloading the SlackBuild... $fileName"
  DwdFile "$sbLink"

  echo "Extracting... tar -zxvf \"$fileName\" \"${fileName%%.*}\"" #look at the space after filename
  tar -zxvf "./${fileName% }" "${fileName%%.*}"                    # that was removed here

  echo "Changing directory to... ${fileName%%.*}/"
  cd "${fileName%%.*}"  # getting in

  echo -e "\nDownloading the sources..."
  for src in $srcLinks; do
    echo "Downloading the source... $src"
    DwdFile "$src"
  done

  echo -e "\n\nExecuting the \"${fileName%%.*}.SlackBuild\""
  if [ $(id -u) -ne 0 ]; then
    printf "root "
    su -c "./${fileName%%.*}.SlackBuild" || exit 2
  else
    ./"${fileName%%.*}.SlackBuild"
  fi
  echo -e "Returning to $TMPDIR"
  cd .. # getting out
}
# }}}
#------------------------------------------------------------------

# Usage: UsageMsg
# Return: void
# Side-effect: Prints the usage message
# {{{
function UsageMsg {
  echo "Usage: sbauto [-s] [-u [packName]] [-h] [-l] url"
  echo "  -s <url>      single-mode: download, compile and install only the given url"
  echo "  -u <url>      don't download or compile just upgradepkg"
  echo "               \"upgradepkg --install new\" upon package of given url"
  echo "  -u <packName> just upgradepkg upon package name"
  echo "  -h            display help information"
#  echo "  -l            generate a file (sbauto.log) containing all content of stdout" 
  echo 
  echo " sbauto (stands for SlackBuilds Automator) makes the repetitive work of "
  echo " installing SlackBuilds for you."
  echo " When it's executed without options the <url> is mandatory."
  echo
  echo " Working flow:"
  echo "   sbauto starts looking for all dependencies your package needs."
  echo
  echo "   If your package needs one or more dependencies..."
  echo "   sbauto makes a tree of dependencies sorted by level. The level 0 is your package,"
  echo "   level 1 are the direct dependecies of your package, level 2 are all"
  echo "   dependencies of each package from the level above (1), and so on."
  echo "   The higher level of the tree is composed of all packages that don't require any"
  echo "   dependency."
  echo
  echo "   After parsing all the dependencies, sbauto will print them on screen for you:"
  echo "     0) 0 packName fullUrl BASE_URL subUrl [depList ...]"
  echo "     ^  ^ ^        ^       ^       ^       ^"
  echo "     |  | |        |       |       |       |"
  echo "     |  | |        |       |       |       List of zero or more dependencies."
  echo "     |  | |        |       |       |"
  echo "     |  | |        |       |       Subdirectories of fullUrl, where your"
  echo "     |  | |        |       |       package can be found."
  echo "     |  | |        |       |"
  echo "     |  | |        |       Main part of fullUrl, address of SlackBuilds.com"
  echo "     |  | |        |"
  echo "     |  | |        Complete url to this package within SlackBuilds.com"
  echo "     |  | |"
  echo "     |  | Package Name (unique)"
  echo "     |  |"
  echo "     |  Level, many packages can have the same level"
  echo "     |"
  echo "     Index, unique value for each package in the tree"
  echo
  echo "   If your package does not need any dependency it just goes on to the"
  echo "   installation of your single-package specified by the given url."
  echo 
  echo "   Then, sbauto will ask if you want to proceed to the Installation process."
  echo "   The installation process actually consists of 3 phases:"
  echo "     1) Download"
  echo "     2) Build from source using the \"packName.SlackBuild\""
  echo "     3) Install the new package or if it already exists just update with the"
  echo "        new one. Or, if the package is already installed and it's the same"
  echo "        version do nothing. This phase is implemented using the"
  echo "       \"upgradepkg --install-new\" command."
  echo
  echo "  If you choosed to continue, sbauto will give you an option to start from"
  echo "  some specific index in the dependency tree, if it exists. Otherwise it will"
  echo "  just proceed to the installation of the single package."
  echo
  echo "  The installation phase will be made for each package of the tree"
  echo "  from bottom to top."
  echo
  echo "  If some error occurs during the installation it will quit immediately."
  echo "  If you type the wrong root password for example the sbauto will quit"
  echo "  in the middle of the process. But you can run again and give the index"
  echo "  where it was stopped before."
}
# }}}

# Usage: MakeTmpDir
# Return: void
# Side-effect: Makes a temp dir to download all SB files and enters it
# {{{
function MakeTmpDir {
  echo -e "\nCreating the $TMPDIR"
  test ! -d "$TMPDIR" && mkdir "$TMPDIR" # only if dir doesn't exist
  echo -e "Changing to $TMPDIR"
  cd "$TMPDIR"
}
# }}}

# Usage: RmTmpDir
# Return: void
# Side-effect: Get out of TMPDIR and prompt to remove it 
# {{{
function RmTmpDir {
  local wantDel
  echo -e "\nFinishing installation..."
  echo -e "Getting out of $TMPDIR"
  cd ..
  sleep 1
  read -p "Do you want to remove all downloaded content [Y/n]? " wantDel
  if [ "$wantDel" != "n" ]; then
    echo "Removing all downloaded content..."
    rm -rv "$TMPDIR" 
  fi
}
# }}}

# Usage: Upgradepkg <pkgName>
# <pkgName> is String
# Return: void
# Side-effect: Run the command 'upgradepkg --install-new' with <pkgName>
# {{{
function Upgradepkg {
  local pkgName="$1"
  local cmd="/sbin/upgradepkg --install-new \"/tmp/$(ls /tmp | grep "$pkgName")\""

  echo -e "\n-------- Upgradepkg $pkgName ------------"
  if [ $(id -u) -eq 0 ]; then
    eval "$cmd"
  else
    printf "root "
    su -c "eval $cmd" || exit 2
  fi
}
# }}}


########### MAIN ############################################ {{{

# The main script inside a function to separate its local
# variables from the global script variables
Main () {  # it also could be "function Main {...}"
  local startFrom
  local doInstall

  if [ $(HasDepsTo "${URL_ARR[0]}") = "true" ]; then
    GetDeps "${URL_ARR[0]}"
    LevelInsert $LEVEL
    Rearrange
    PrintDepTree
    echo -e "\n"
    read -p "Proceed to the Installation of them all [y/N] ?  " doInstall
    if [ "$doInstall" = "y" ] || [ "$doInstall" = "Y" ]; then
      read -p "Do you want to start from what index [default: $(($INDEX -1))]? " startFrom
      startFrom=${startFrom:-$(($INDEX -1))}
      echo "startFrom = $startFrom"
      if test $startFrom -ge 0; then 
        INDEX=$(($startFrom + 1)) 
      else
        echo "Index is a number >= 0"; exit 3
      fi
      MakeTmpDir
      for ((i = $INDEX - 1; i >= 0; i--)); do
        Install "$(TreeElem $i 2)"
        Upgradepkg "$(TreeElem $i 1)"
      done
      RmTmpDir
    fi
  else
    # The GIVEN_URL has not dependencies
    echo -e "\n\nThe package $(GetName "${URL_ARR[0]}") has not dependencies"
    read -p "Proceed to the Installation of this package [y/N] ?  " doInstall
    if [ "$doInstall" = "y" ]; then
      MakeTmpDir
      Install "${URL_ARR[0]}"
      Upgradepkg "$(GetName "${URL_ARR[0]}")"
      RmTmpDir
    fi
  fi
}

# ********* Global Variables Declaration ************* {{{
# DEP_TREE array structure. Each line is:
#   [level] [packName] [url] [BASE_URL] [subUrl] [depsList]
# URL_ARR array structure. Each line is:
#   [fullUrl] [BASE_URL] [subUrl]
# DEPS_ARR is a variable length list with the subUrl of the deps
declare -ag DEP_TREE
declare -ag URL_ARR
declare -ag DEPS_ARR
export TMPDIR="./tmp-sbauto"
export GIVEN_URL
export BASE_URL
export LEVEL=0
export INDEX=0
export DEBUG_MODE="off"  # on / off
# **************************************************** }}}

# *********** Processing Options *************** {{{
#if getopt :s:u:hl "$@" | grep -e "-l" &> /dev/null
#then
#  echo -e "\nHas the -l option"
#
#  echo -e "Removing the option -l"
#  set -- $(getopt :s:u:hl $@ | sed 's/-l //g')
#
#  echo "eval \" $0 $@ | tee \"$(GetName "${*#*-- }")-sbauto.log\" \""
#  eval "$0 $@ | tee \"$(GetName "${*#*-- }")-sbauto.log\""
#  exit 0
#fi

while getopts :s:u:h option
do
  case "$option" in
    s) MakeTmpDir
       Install "${OPTARG}"
       Upgradepkg "$(GetName "${OPTARG}")"
       RmTmpDir
       exit 0 ;;

    u) if echo "${OPTARG}" | grep "http" &> /dev/null
       then
         Upgradepkg "$(GetName "${OPTARG}")"
       else
         Upgradepkg "${OPTARG}"
       fi
       exit 0 ;;

    h) UsageMsg
       exit 0 ;;

    *) echo -e "\nInvalid Option!"
       UsageMsg
       exit 1 ;;
  esac
done

shift $[ $OPTIND - 1 ]  # 2 ways to do inline math: $((1+1)) or $[ 1+1 ]
# ******************************************************* }}} 

# The url is a mandatory argument
if [ -n "$1" ]; then
  GIVEN_URL="${1}"
else
  UsageMsg
  exit 4
fi

# Generating the URL_ARR with the argument passed $1
ParseUrl "${GIVEN_URL}"
BASE_URL="${URL_ARR[1]}"

Main

#echo -e "\nvars:\nLEVEL = $LEVEL\nINDEX = $INDEX"
#echo -e "\tURL_ARR = ${URL_ARR[*]}\n\tDEPS_ARR = ${DEPS_ARR[*]}"

############################################################# }}}

