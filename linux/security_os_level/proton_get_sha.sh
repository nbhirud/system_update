#!/bin/sh

# set -eux

# JSON_PATH="/home/nbhirud/nb/Downloads/proton_ag_downloads_2025-09-22_13-01-59"
# JSON_FILENAME="ProtonAuthenticator_version.json"

JSON_PATH=$1
JSON_FILENAME=$2

# jq '.Releases[0].File' $JSON_PATH/$JSON_FILENAME | jq length

# latest_file=$(jq '.Releases[0].File' $JSON_PATH/$JSON_FILENAME)
# echo $latest_file

exit # TODO remove after completing the below new code

release_count=$(jq '.Releases' "$JSON_PATH"/"$JSON_FILENAME" | jq length)
# echo $release_count

i_stable=0

# i=0
# while [ $i -lt "$release_count" ]
# do
#     # URL=$(jq ".Releases[0].File[$i].Url" "$JSON_PATH"/"$JSON_FILENAME")
#     CategoryName=$(jq ".Releases[$i].CategoryName" "$JSON_PATH"/"$JSON_FILENAME")
#     if echo "$CategoryName" | grep -q "Stable" ;
#     then
#         i_stable=$i
#     fi
#     i=$(( $i + 1 ))
# done

distro_count=$(jq '.Releases[i_stable].File' "$JSON_PATH"/"$JSON_FILENAME" | jq length)
# echo $distro_count

i=0
while [ $i -lt "$distro_count" ]
do
    URL=$(jq ".Releases[i_stable].File[$i].Url" "$JSON_PATH"/"$JSON_FILENAME")

    # if grep -q foo file.txt; then
    #     echo "file.txt contains foo"

    if echo "$URL" | grep -q ".rpm" ;
    then
        # echo $i
        # echo "$URL found it"
        Sha512CheckSum=$(jq ".Releases[i_stable].File[$i].Sha512CheckSum" "$JSON_PATH"/"$JSON_FILENAME")
        echo "$Sha512CheckSum"
    fi

    i=$(( $i + 1 ))
done


