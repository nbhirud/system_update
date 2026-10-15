#!/bin/sh

set -eux

# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html


curl -fsSL https://awscli.amazonaws.com/v2/install.sh | bash

aws update

aws --version

