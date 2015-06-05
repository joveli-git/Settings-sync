# Settings-sync
Simple script example to sync web app settings with api

#Overview
This script is using curl command for API HTTP requests posting
and jq lib for json output parsing.
Jq information: http://stedolan.github.io/jq/

Script could receive 2 command line parameters: config file name and log file name.
If config file parameter is not specified in command line, there is used default name.
If default config not found, script is asking all parameters in dialog during runtime.
Default config file has all example params/values for RC environment.

If log file is missing, it's created with default name. Timestamp is writing to the end of file name.
All error messages are printed to log file and to console output.

Info messages are printed to the log file and if parameter console=on, they are logging to console out as well.
Information about updated rules and execution errors could be found in log file with latest timestamp.

#Example
Simple one
$ copyWAF.sh
With 1 command line param
$ copyWAF.sh copyWAF_RC.conf
With 2 command line params
$ copyWAF.sh copyWAF_RC.conf test.log
