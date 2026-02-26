# Publishing Checklist for Mac Storage Cleanup

## Before Publishing to GitHub

### 1. Clean Up Repository
```bash
# Remove user-specific files (already in .gitignore)
git rm -r --cached MacStorageCleanupApp.xcodeproj/xcuserdata/
git rm -r --cached MacStorageCleanupApp.xcodeproj/project.xcworkspace/xcuserdata/
git rm -r --cached MacStorageCleanup/.swiftpm/xcode/xcuserdata/

# Remove DerivedData references if any
find . -name "DerivedData" -exec rm -rf {} +
```

### 2. Update Personal Information
- [ ] Update README.md with your GitHub username
- [ ] Update README.md with your email
- [ ] Update LICENSE with your name/organization
- [ ] Update About tab copyright in PreferencesWindow.swift

### 3. Version Information
- [ ] Set version in Info.plist (CFBundleShortVersionString)
- [ ] Set build number in Info.plist (CFBundleVersion)
- [ ] Update CHANGELOG.md with release date

### 4. Code Review
- [ ] Remove any hardcoded credentials or API keys
- [ ] Remove debug print statements (or keep only essential ones)
- [ ] Ensure all TODOs are addressed or documented
- [ ] Check for any personal information in comments

### 5. Testing
- [ ] Run all unit tests
- [ ] Test on clean macOS installation if possible
- [ ] Test with Debug Mode enabled
- [ ] Test all major features
- [ ] Verify permissions work correctly

### 6. Documentation
- [ ] README.md is complete and accurate
- [ ] CONTRIBUTING.md is clear
- [ ] LICENSE is appropriate
- [ ] Code comments are helpful
- [ ] API documentation is complete

### 7. Initialize Git Repository
```bash
cd /Users/tomer/Develop/MacCleaner
git init
git add .
git commit -m "Initial commit: Mac Storage Cleanup v1.0.0"
```

### 8. Create GitHub Repository
1. Go to https://github.com/new
2. Repository name: `MacCleaner` or `mac-storage-cleanup`
3. Description: "A powerful macOS app to clean up storage and free up disk space"
4. Choose Public or Private
5. Don't initialize with README (we already have one)
6. Create repository

### 9. Push to GitHub
```bash
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
git branch -M main
git push -u origin main
```

### 10. GitHub Repository Settings
- [ ] Add topics: `macos`, `swift`, `swiftui`, `storage-cleanup`, `disk-cleanup`
- [ ] Add description
- [ ] Add website (if you have one)
- [ ] Enable Issues
- [ ] Enable Discussions (optional)
- [ ] Set up branch protection rules (optional)

### 11. Create First Release
1. Go to Releases > Create a new release
2. Tag: `v1.0.0`
3. Title: `Mac Storage Cleanup v1.0.0`
4. Description: Copy from CHANGELOG.md
5. Attach compiled .app as binary (optional)
6. Mark as latest release
7. Publish release

### 12. Optional Enhancements
- [ ] Add screenshots to README
- [ ] Create demo video/GIF
- [ ] Set up GitHub Actions for CI/CD
- [ ] Add code coverage reporting
- [ ] Create project website
- [ ] Submit to Mac App Store (requires Apple Developer account)
- [ ] Add social media links
- [ ] Create logo/icon

## Post-Publishing

### Promote Your Project
- Share on Twitter/X with #macOS #Swift hashtags
- Post on Reddit (r/macapps, r/swift, r/macOS)
- Share on Hacker News
- Write a blog post about the development process
- Share in Swift/macOS developer communities

### Maintain
- Respond to issues promptly
- Review and merge pull requests
- Keep dependencies updated
- Release updates regularly
- Engage with the community

## Quick Commands Reference

```bash
# Check git status
git status

# Add all files
git add .

# Commit changes
git commit -m "Your message"

# Push to GitHub
git push

# Create and push a tag
git tag v1.0.0
git push origin v1.0.0

# View commit history
git log --oneline

# Check remote
git remote -v
```

## Need Help?
- GitHub Docs: https://docs.github.com
- Git Basics: https://git-scm.com/book/en/v2
- Swift Package Manager: https://swift.org/package-manager/
