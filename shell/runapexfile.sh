#!/bin/bash

# Create a logs directory if it doesn't exist
LOG_DIR="./logs"
mkdir -p $LOG_DIR

# Get the current timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Log file path
LOG_FILE="$LOG_DIR/run_log_$TIMESTAMP.log"

# Salesforce CLI alias for the org
ORG_ALIAS="your_org_alias"

# Apex script file path
APEX_SCRIPT_PATH="../apex/UpdateBilligJunctionURLs.apex"

NUM_RUNS=2
Run_COUNT=1

# Loop to run the Apex script
while [ $Run_COUNT -le $NUM_RUNS ]; do
     echo "Running Apex script..." 
      # Run the Apex script using Salesforce CLI
    #sfdx force:apex:execute -u $ORG_ALIAS -f $APEX_SCRIPT_PATH
    sf apex run --file $APEX_SCRIPT_PATH  >> $LOG_FILE 2>&1
    # Check the result of the last command
    if [ $? -ne 0 ]; then
        echo "Error executing Apex script. Exiting loop."
        break
    fi
    echo "Run $Run_COUNT completed."
    echo "Waiting for 5 seconds before running the next iteration..."
    # Add a delay if needed to avoid hitting limits
    sleep 5
      Run_COUNT=$((Run_COUNT + 1))
    echo "Starting next iteration..."
 echo " completed $Run_COUNT out of $NUM_RUNS"
done   
echo "Apex script run completed."