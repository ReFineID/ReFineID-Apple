# ReFineID for Apple platforms

ReFineID makes Finnish identity cards usable through Apple platform security frameworks. 

## Building

Requires Xcode 26 on macOS 26. From a fresh clone, no other setup:

```sh
xcodebuild -project ReFineID.xcodeproj -scheme ReFineID build
xcodebuild -project ReFineID.xcodeproj -scheme ReFineID test
```
