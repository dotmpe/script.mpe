package_environments__0=development
package_id=script.mpe
package_version=0.0.0-dev
package_main=script.mpe
package_type=application/x-project-mpe
package_pd_meta_test="vchk -python:test/main.py bats-specs bats"
package_pd_meta_git_hooks_pre_commit=./tools/git-hooks/pre-commit.sh
package_pd_meta_init="./install-dependencies.sh git"
package_pd_meta_check="vchk bats-specs"
