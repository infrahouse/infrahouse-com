# infrahouse.com website

The website uses [hugo](https://gohugo.io/) with a [Hugoplate](https://github.com/zeon-studio/hugoplate) template.

# Development

Checkout the source code.

```shell
git clone git@github.com:infrahouse/infrahouse-com.git
cd infrahouse-com
```

Create a branch
```shell
git checkout -b new-feature
```

To run a development instance locally, execute

```shell
make start
```
The website is available on http://localhost:1313/ .

When the local copy is ready for submission, create a pull request (Make sure you have installed [GitHub CLI](https://cli.github.com/)).

```shell
git commit -am "Branch new awesome feature"
gh pr create
```
If pull request checks are green, merge the PR
```shell
gh pr merge -ds
```
After about 30 minutes, the new version will be available on https://staging.infrahouse.com

# Deployment to production

TBD
