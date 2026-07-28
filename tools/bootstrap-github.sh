#!/bin/bash
# One-shot setup of the GitHub side of the port:
#   1. fork the kernel tree that carries the Ubuntu Touch patches
#   2. point deviceinfo at your fork
#   3. create this repo on GitHub and push it, which starts the build
#
# Requires an authenticated gh:  gh auth login
set -euo pipefail

UPSTREAM_KERNEL="mukahraman/kernel_samsung_sm8250"
KERNEL_BRANCH="ubuntu-touch"
PORT_REPO_NAME="${PORT_REPO_NAME:-gts7l-ubports}"
# public => unlimited Actions minutes; set to --private if you prefer
VISIBILITY="${VISIBILITY:---public}"

command -v gh >/dev/null || { echo "gh not installed"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "run: gh auth login"; exit 1; }

USER_LOGIN="$(gh api user --jq .login)"

echo "==> forking $UPSTREAM_KERNEL"
if gh repo view "$USER_LOGIN/kernel_samsung_sm8250" >/dev/null 2>&1; then
    echo "    fork already exists, skipping"
else
    gh repo fork "$UPSTREAM_KERNEL" --clone=false
    # forks are created asynchronously
    for _ in $(seq 30); do
        gh repo view "$USER_LOGIN/kernel_samsung_sm8250" >/dev/null 2>&1 && break
        sleep 5
    done
fi

echo "==> checking that branch '$KERNEL_BRANCH' is present in the fork"
git ls-remote --heads "https://github.com/$USER_LOGIN/kernel_samsung_sm8250" "$KERNEL_BRANCH" \
    | grep -q "$KERNEL_BRANCH" || {
        echo "branch missing in fork — gh only forks the default branch on some plans."
        echo "Fix with:"
        echo "  git clone -b $KERNEL_BRANCH --single-branch https://github.com/$UPSTREAM_KERNEL k"
        echo "  cd k && git remote set-url origin https://github.com/$USER_LOGIN/kernel_samsung_sm8250 && git push -u origin $KERNEL_BRANCH"
        exit 1
    }

echo "==> pointing deviceinfo at the fork"
sed -i.bak "s|^deviceinfo_kernel_source=.*|deviceinfo_kernel_source=\"https://github.com/$USER_LOGIN/kernel_samsung_sm8250\"|" deviceinfo
rm -f deviceinfo.bak
git add deviceinfo
git diff --cached --quiet || git commit -m "deviceinfo: build from own kernel fork"

echo "==> creating and pushing $USER_LOGIN/$PORT_REPO_NAME"
if gh repo view "$USER_LOGIN/$PORT_REPO_NAME" >/dev/null 2>&1; then
    git remote get-url origin >/dev/null 2>&1 || \
        git remote add origin "https://github.com/$USER_LOGIN/$PORT_REPO_NAME"
    git push -u origin HEAD
else
    gh repo create "$PORT_REPO_NAME" $VISIBILITY --source=. --remote=origin --push \
        --description "Ubuntu Touch port for Samsung Galaxy Tab S7 LTE (SM-T875 / gts7l)"
fi

echo "==> build started, follow it with:"
echo "    gh run watch"
