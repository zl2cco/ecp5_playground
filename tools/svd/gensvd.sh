#!/bin/sh

svd patch picorv32-soc.yaml
xmllint --format svdtemplate.svd.patched > picorv32-soc.svd
