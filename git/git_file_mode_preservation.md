
# executable bit

Git tracks the executable bit for files, specifically the 
- `100755` executable permissions
- `100644` non-executable permissions

## Standard Git commands handle the executable bit automatically:
- `git add`: Automatically detects when a file's permissions have changed (e.g., after running `chmod +x`) and stages the permission change along with the file contents.
- `git commit`: Saves the executable status (`100755`) into the commit history.
- `git push`: Uploads the tracked permissions to the remote repository.

```
chmod +x scriptpath.sh
git add scriptpath.sh
git commit
```

## When is git update-index used instead?

You do not need to run `git update-index` for standard workflows. You only need `git update-index` for edge cases or manual overrides - such as forcing Git to change or ignore a file's tracked permissions independently of the local filesystem (e.g., using `git update-index --chmod=+x`). For normal development, standard git add, commit, and push are all you need.

```
# Mark a script executable in Git
git update-index --chmod=+x scriptpath.sh

# Mark it non-executable in Git
git update-index --chmod=-x scriptpath.sh

# Verify the mode staged in Git
git ls-files --stage scriptpath.sh
```

## Important distinction

- `chmod +x scriptpath.sh` changes the filesystem permission. Git detects the change and can stage it.

- `git update-index --chmod=+x scriptpath.sh` changes the executable bit in Git's index (staging area). It doesn't necessarily change the file's actual filesystem permission.

## Cloning

When you clone the repo on another Linux machine, Git will restore the executable bit. Verify this using:
```
git ls-files --stage scriptpath.sh
```



## Additional reading
https://git-scm.com/book/en/v2/Git-Internals-Git-Objects
https://git-scm.com/docs/gitglossary
https://git-scm.com/docs/git-config
https://git-scm.com/docs/git-update-index

