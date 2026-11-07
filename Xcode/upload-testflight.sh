#!/bin/zsh
# Builds PinBoard with its widgets and its share extension (PinBoard.xcodeproj: the app from
# ../PinBoard and App/, the widget extension from PinBoardWidgets/, the share extension from
# PinBoardShare/ — both are embedded in the app, so they are archived and uploaded with it) and
# uploads it to TestFlight.
# Usage: ./upload-testflight.sh <build number>   (each upload needs a higher number than the last)
#
# The App IDs com.silentdiffusion.pinboard2, com.silentdiffusion.pinboard2.widgets and
# com.silentdiffusion.pinboard2.share all need the App Group group.com.silentdiffusion.pinboard2 (the
# widgets' snapshot and the share sheet's inbox go through it), and the app's ID also iCloud with the
# iCloud.com.silentdiffusion.pinboard2 container, on developer.apple.com.
set -euo pipefail

build=${1:?Give the build number, e.g. ./upload-testflight.sh 8}
here=${0:A:h}
cd "$here"

python3 make-project.py   # picks up files added to ../PinBoard since the last time

# Archives and exports go to the repo's _archives/ folder (git-excluded) on the same drive as the
# repo, not to ~/Library/Developer/Xcode/Archives on the small internal drive. (Xcode's Organizer
# only lists archives from its own folder; open one from here by double-clicking it in Finder.)
out=${here:h}/_archives
archive=$out/xcarchives/$(date +%Y-%m-%d)/PinBoard-1.0-$build.xcarchive
export_dir=$out/exports/PinBoard-1.0-$build
mkdir -p "${archive:h}" "$export_dir"

xcodebuild -project PinBoard.xcodeproj -scheme PinBoard -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$build" \
    archive

xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist ExportOptions.plist \
    -exportPath "$export_dir" -allowProvisioningUpdates
