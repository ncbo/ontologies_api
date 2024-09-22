#!/bin/bash
# generates solr configsets by merging _default configset with config files in config/solr
# _default is copied from sorl distribuion solr-8.10.1/server/solr/configsets/_default/

#cd solr/configsets
ld_config='config/solr'
configsets='test/solr/configsets'
[ -d ${configsets}/property_search ] && rm -Rf ${configsets}/property_search
[ -d ${configsets}/term_search ] && rm -Rf ${configsets}/term_search
if [[ ! -d ${ld_config}/property_search ]]; then
  echo 'cant find ld solr config sets'
  exit 1
fi
if [[ ! -d ${configsets}/_default/conf ]]; then
  echo 'cant find default solr configset'
  exit 1
fi
mkdir -p ${configsets}/property_search/conf
mkdir -p ${configsets}/term_search/conf
cp -a ${configsets}/_default/conf/* ${configsets}/property_search/conf/
cp -a ${configsets}/_default/conf/* ${configsets}/term_search/conf/
cp -a $ld_config/property_search/* ${configsets}/property_search/conf
cp -a $ld_config/term_search/* ${configsets}/term_search/conf

