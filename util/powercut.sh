#!/usr/bin/env bash

powerCuts="Live Detailed Power Cuts"

dataSources=$(curl -L -s https://connecteddata.nationalgrid.co.uk/dataset/live-power-cuts/datapackage.json)

powerCutsDataSource=$(echo "$dataSources" | jq ".resources[] | select(.name | contains (\"$powerCuts\"))")
powerCutsDataUrl=$(echo "$powerCutsDataSource" | jq -r ".url")
powerCutsCsvData=$(curl -L -s "$powerCutsDataUrl")

python3 -c "

csvData = '''$powerCutsCsvData'''

print(csvData)

"
