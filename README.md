EPGPlayer
===

## Building

### Build VLCKit

```bash
git clone https://github.com/imxieyi/vlckit.git
cd vlckit
./compileAndBuildVLCKit.sh -f -a all -v
./compileAndBuildVLCKit.sh -x -a all -v
cd build
xcodebuild -create-xcframework \
    -archive VLCKit-iphoneos.xcarchive -framework VLCKit.framework \
    -archive VLCKit-iphonesimulator.xcarchive -framework VLCKit.framework \
    -archive VLCKit-macosx.xcarchive -framework VLCKit.framework \
    -output VLCKit.xcframework
```
