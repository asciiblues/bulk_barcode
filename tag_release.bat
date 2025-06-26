# Check your current branch
git branch

# See if your tag exists locally and remotely
git tag

# Delete tag locally and remotely if necessary
git tag -d v1.1.5
git push origin :refs/tags/v1.1.5

# Re-create tag at current commit
git tag -a v1.1.5 -m "+ Added space for barcode/ QR separator."
git push origin v1.1.5