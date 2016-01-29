#!/usr/bin/env bash

# Virtuoso import script
# ----------------------
  # Import data into an open virtuoso server
  #
  # Configs as paramater:
  # host: $1
  # port: $2
  # user: $3
  # pwd: $4
# 

set -o nounset # will ensure all variables are given/set

bin="isql-vt"
host="$1"
port=$2
user="$3"
password="$4"
store_import_dir='/import_store' # folder for the data, needs to be in virtuosos allowed dirs in virtuoso config.ini
max_size=300000000 # max size of a dataset in bytes (300MB)

run_virtuoso_cmd () {
  VIRT_OUTPUT=`echo "$1" | "$bin" -H "$host" -S "$port" -U "$user" -P "$password" 2>&1`
  VIRT_RETCODE=$?
  quiet=false
  
  if [[ $# -ge 2 ]] && [[ $2 = "quiet" ]] ; then
    quiet=true
  fi
  
  if [[ $VIRT_RETCODE -eq 0 ]]; then
    if [[ $quiet = false ]] ; then
      echo "$VIRT_OUTPUT" | tail -n+5 | perl -pe 's|^SQL> ||g'
    fi
    return 0
  else
    if [[ $quiet = false ]] ; then
      echo -e "[ERROR] running these commands in virtuoso:\n$1\nerror code: $VIRT_RETCODE\noutput:"
      echo "$VIRT_OUTPUT"
    fi
    let 'ret = VIRT_RETCODE + 128'
    return $ret
  fi
}

cd "$store_import_dir"

# convert all files to n-triples
for file in `ls *.nq *.owl *.rdf *.trig *.ttl *.xml *.gz 2> /dev/null`; do
  if [ -e ${file} ]; then
    echo "[INFO ] converting ${file} to n-triples..."
      rapper $file -i guess -o ntriples >> ${file}.nt
  fi
done

# walk al rdf-n-triple files
for file in `ls *.nt 2> /dev/null`; do  
  filename="${file%.*}"

  # get graph from filename.ext.graph or extract from filename itself
  if [ -e ${file}.graph ]; then
    graph=`head -n1 ${file}.graph`
  else
    graph="http://${filename}/"
  fi

  size=$(stat -c%s "$file")

  # test if file is too big
  if [ $size -gt $max_size ]; then
    echo "[INFO] File ${file} is too big. Split into smaller pieces..."

    mkdir -p ./splitted_data/$filename

    split -C 300m $file "./splitted_data/${filename}/file"

    echo "[INFO] registring parts of ${file} for import to graph ${graph}"
    run_virtuoso_cmd "ld_dir ('${store_import_dir}/splitted_data/${filename}', '*', '${graph}');"
  else
    echo "[INFO] registring ${file} for import to graph ${graph}"
    run_virtuoso_cmd "ld_dir ('${store_import_dir}', '${file}', '${graph}');"
  fi

done

echo '[INFO] Starting load process...';
run_virtuoso_cmd "rdf_loader_run();"
# TODO: why does parallelizing not seems faster??
# run_virtuoso_cmd "rdf_loader_run();" &
# run_virtuoso_cmd "rdf_loader_run();" &
# run_virtuoso_cmd "rdf_loader_run();" &
# run_virtuoso_cmd "rdf_loader_run();" &
# wait

echo "[INFO] making checkpoint..."
run_virtuoso_cmd 'checkpoint;'

# delete created folder for splitted data if exists
rm -rf ./splitted_data

echo "[INFO] done loading graphs"