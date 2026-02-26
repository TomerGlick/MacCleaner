#!/bin/bash

# Script to generate app icons from SF Symbol
# This creates a simple icon using the internaldrive.fill symbol

ICON_DIR="/Users/tomer/Develop/MacCleaner/MacStorageCleanupApp/Assets.xcassets/AppIcon.appiconset"

# Create a temporary Swift script to generate icons
cat > /tmp/generate_icon.swift << 'EOF'
import Cocoa
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = CommandLine.arguments[1]

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    // Background gradient
    let gradient = NSGradient(colors: [
        NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.0, green: 0.38, blue: 0.9, alpha: 1.0)
    ])
    gradient?.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: 90)
    
    // Draw SF Symbol
    if let symbolImage = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil) {
        let symbolSize = CGFloat(size) * 0.6
        let symbolRect = NSRect(
            x: (CGFloat(size) - symbolSize) / 2,
            y: (CGFloat(size) - symbolSize) / 2,
            width: symbolSize,
            height: symbolSize
        )
        
        symbolImage.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    image.unlockFocus()
    
    // Save as PNG
    if let tiffData = image.tiffRepresentation,
       let bitmapImage = NSBitmapImageRep(data: tiffData),
       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
        let filename = "\(outputDir)/icon_\(size)x\(size).png"
        try? pngData.write(to: URL(fileURLWithPath: filename))
        print("Generated: \(filename)")
    }
}
EOF

# Run the Swift script
swift /tmp/generate_icon.swift "$ICON_DIR"

# Update Contents.json with actual filenames
cat > "$ICON_DIR/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_64x64.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_1024x1024.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "✅ App icons generated successfully!"
echo "📁 Location: $ICON_DIR"
