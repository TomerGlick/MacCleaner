# Screenshot Guide

## Taking Screenshots for README

### What to Capture

1. **Main Window** (`main-window.png`)
   - Storage visualization with pie chart
   - Category breakdown visible
   - Show some actual data

2. **Cleanup Candidates** (`cleanup-candidates.png`)
   - List of items to clean
   - Show file sizes
   - Multiple categories selected

3. **Cleanup Progress** (`cleanup-progress.png`)
   - Progress bar active
   - Items being cleaned

### How to Take Screenshots

**Option 1: Window Screenshot (Recommended)**
```bash
# Press: Cmd + Shift + 4 + Space
# Click on the window
# Saves to Desktop with shadow
```

**Option 2: Area Screenshot**
```bash
# Press: Cmd + Shift + 4
# Drag to select area
# Saves to Desktop
```

**Option 3: Screenshot Tool**
```bash
# Press: Cmd + Shift + 5
# Choose window or area
# Click Options to remove shadow if needed
```

### After Taking Screenshots

1. Move screenshots to the `screenshots/` folder:
```bash
mv ~/Desktop/Screenshot*.png screenshots/
```

2. Rename them:
```bash
cd screenshots
mv "Screenshot 2026-02-26 at 20.15.00.png" main-window.png
mv "Screenshot 2026-02-26 at 20.16.00.png" cleanup-candidates.png
mv "Screenshot 2026-02-26 at 20.17.00.png" cleanup-progress.png
```

3. Commit and push:
```bash
git add screenshots/
git commit -m "Add screenshots to README"
git push
```

### Tips

- Use light mode for better visibility
- Make window full size but not fullscreen
- Show realistic data (not empty states)
- Keep window shadows for professional look
- Use PNG format for best quality
- Optimize images if needed: `brew install imageoptim-cli`

### Image Optimization (Optional)

```bash
# Install optimizer
brew install imageoptim-cli

# Optimize all screenshots
imageoptim screenshots/*.png
```

This reduces file size without losing quality.
