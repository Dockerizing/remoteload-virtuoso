#!/usr/bin/env bash

# Init the import scripts for all stores
# ------------------------
#   - get stores from docker-compose environment vars STORE_[index] (see README)
#   - if ssh is available:
#       . copy import data, send store-specific import-script and execute
#   - after import, start nginx as request ping service and hanging around idle
# ------------------------

store_import_dir='/import_store'
: ${CONNECTION_ATTEMPTS:=10}

# main function
main() {
    
    if [ ! -d ${store_import_dir} ] || [ "$(ls -A ${store_import_dir} 2> /dev/null)" == "" ]; then
        echo "[WARNING] import folder is empty. Will not load any data"
        start_request_service
    fi

    cd "$store_import_dir"

    bz2_to_gz "$store_import_dir"

    # load and parse stores from env_stores
    i=1
    stores="STORE_${i}"
    while [ -n "${!stores}" ]
    do
        store=${!stores}
        # echo "[INFO] store $i config: '${store}'"

        URI=""
        HOST=""
        PORT=""
        TYPE=""
        USER=""
        PWD=""

        get_store_config "$store"

        echo "[INFO] got store $i (${URI})"
        # echo "type: $TYPE , uri: $URI , user: $USER , pwd: $PWD"
        if [[ -z "$URI" || -z "$HOST" ]] ; then
            echo "[ERROR] empty host or uri of store $i. If your are using Docker Compose check the links and environment ids."
            exit 1
        fi  

        echo "[INFO] waiting for store $i to come online"
        test_connection "${CONNECTION_ATTEMPTS}" "${HOST}" "${PORT}"
        if [ $? -eq 2 ]; then
            echo "[ERROR] store ${HOST}:${PORT} not reachable"
            exit 1
        else
            echo "[INFO] store $i connection OK"
        fi  

        /import-virtuoso.sh "${HOST}" "${PORT}" "${USER}" "${PWD}"
        
        let "i=$i+1"
        stores="STORE_${i}"
    done

    start_request_service

} # end of main


# test connection to host and port
test_connection () {
    if [[ -z $1 || -z $2 ]]; then
        echo "[ERROR] missing argument: retry attempts or host"
        exit 1
    fi

    t=$1
    host=$2
    port=$3

    if [[ -z $port ]]; then
        echo "[WARNING] no port given for connection-test, set 80 as default."
        port=80
    fi
    
    nc -w 1 "$host" $port < /dev/null;
    #curl --output /dev/null --silent --head --fail "$host"
    while [[ $? -ne 0 ]] ;
    do
        echo -n "..."
        sleep 2
        echo -n $t
        let "t=$t-1"
        if [ $t -eq 0 ]
        then
            echo "...timeout"
            return 2
        fi
        nc -w 1 "$host" $port < /dev/null;
    done
    echo ""
}


bz2_to_gz () {
    if [[ -z "$1" || ! -d "$1"  ]]; then
        echo "[ERROR] not a valid directory path: $wd"
        exit 1
    fi

    wd="$1"
    bz2_archives=( "$wd"/*bz2 )
    bz2_archive_count=${#bz2_archives[@]}
    if [[ $bz2_archive_count -eq 0 || ( $bz2_archive_count -eq 1 && "$bz2_archives" == "${wd}/*bz2" ) ]]; then
        return 0
    fi

    echo "[INFO] converting $bz2_archive_count bzip2 archives to gzip:"
    for archive in ${bz2_archives[@]}; do
        echo "[INFO] converting $archive"
        pbzip2 -dc $archive | pigz - > ${archive%bz2}gz
        rm $archive
    done
}

# get uri from linked docker container
uri_store_matching() {
    uri=$1
    # may get uri from %store_id%
    #if [[ "$uri" =~ %[A-Za-z]+% ]] ; then       
    if [[ "$uri" =~ %%.*%% ]] ; then
        match=$BASH_REMATCH # = %%store_id%%
        appendix=${uri//*$match/}
        prefix=${uri//$match*/}
        store_id=${match//\%/}
        
        store_tcp_var="${store_id^^}_PORT" # address variable with uppercased store_id
        store_tcp=${!store_tcp_var} #  store tcp address
        store_tcp=${store_tcp//*\//} # remove tcp://
        store_tcp=${store_tcp//:*/} # remove port

        uri=${prefix}${store_tcp}${appendix}
        #uri=${uri/$store_tcp/$match/}
    fi
    echo $uri
}

# get config (URI, TYPE, USER, PWD) from string
get_store_config () {
    if [[ -z $1 ]]; then
        echo "[ERROR] missing argument: store variable"
        exit 1
    fi
    store=$1

    for str in $store
    do
        # split string at delimiter '=>'
        arr=(${str//=>/ })
        key=${arr[0]}
        val=${arr[1]}

        # echo "${key} = ${val}"
        case "$key" in
            "uri" )
                URI=$(uri_store_matching $val)            
                HOST=${URI//*:\/\//} # remove http://
                HOST=${HOST//:*/} # remove port/path
                HOST=${HOST//\/*/}

                PORT=${URI//*:/}                
                PORT=${PORT//\/*/}            
                ;;
            "type" )
                TYPE=$val
                ;;
            "user" )
                USER=$val
                ;;
            "pwd" ) 
                PWD=$val
                ;;
        esac    
    done
}


start_request_service () {
    echo "[INFO] Done. Hanging around idle and listen on port 80 for requests"
    nc -kl 80
}

# start main
main