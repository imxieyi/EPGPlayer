// swift-tools-version: 6.0
//
// Decoder-only build of libaribcaption 1.1.1 (https://github.com/xqq/libaribcaption),
// used to extract ARIB STD-B24 caption text from MPEG-TS files.
// Sources are vendored unmodified except for the pre-generated aribcc_config.h.

import PackageDescription

let package = Package(
    name: "LibARIBCaption",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
    ],
    products: [
        .library(name: "LibARIBCaption", targets: ["LibARIBCaption"]),
    ],
    targets: [
        .target(
            name: "LibARIBCaption",
            cSettings: [
                .headerSearchPath("src"),
                .define("ARIBCC_IMPLEMENTATION"),
            ],
            cxxSettings: [
                .headerSearchPath("src"),
                .define("ARIBCC_IMPLEMENTATION"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
