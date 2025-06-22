# Check your current branch
git branch

# See if your tag exists locally and remotely
git tag

# Delete tag locally and remotely if necessary
git tag -d v1.1.4
git push origin :refs/tags/v1.1.4

# Re-create tag at current commit
git tag -a v1.1.4 -m "✓ Fixed 'Use New Line Separator' CheckBoxTile before 'Read Data Column' Button"
git push origin v1.1.4