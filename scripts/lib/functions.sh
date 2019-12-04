#!/bin/bash

function backup_config() {
    origin_file=$1

    test -f $origin_file || exit 0
    test -f $origin_file.orig || cp -f $origin_file $origin_file.orig
    test -f $origin_file.orig && cp $origin_file.orig $origin_file
}

function print_install {
    echo -e "\e[34m$1 \e[0m"
}

function print_header {
    echo -e "\e[44m> $1 \e[0m"
}

function print_success {
    echo -e "\e[42m$1 \e[0m"
}

function echocolor {
    echo -e "\e[93m$1 \e[0m"
}

function ops_edit {
    crudini --set $1 $2 $3 $4
}

function ops_del {
    crudini --del $1 $2 $3
}
