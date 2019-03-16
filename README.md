# [DropboxSDK](https://github.com/eschnett/DropboxSDK.jl)

A Julia package to access Dropbox via its
[API](https://www.dropbox.com/developers/documentation/http).

[![Build Status (Travis)](https://travis-ci.org/eschnett/DropboxSDK.jl.svg?branch=master)](https://travis-ci.org/eschnett/DropboxSDK.jl)
[![Build status (Appveyor)](https://ci.appveyor.com/api/projects/status/eo7ajcctw4666pxm?svg=true)](https://ci.appveyor.com/project/eschnett/dropboxsdk-jl)
[![Coverage Status (Coveralls)](https://coveralls.io/repos/github/eschnett/DropboxSDK.jl/badge.svg?branch=master)](https://coveralls.io/github/eschnett/DropboxSDK.jl?branch=master)
<!---
[![DOI](https://zenodo.org/badge/144600920.svg)](https://zenodo.org/badge/latestdoi/144600920)
-->



## Setup

(Discuss authorization tokens. Upshot: get your token
[here](https://www.dropbox.com/developers/apps/create), then save it
into a file `secrets.http` that should look like

```
access_token:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

A token is like a password; treat it accordingly -- make sure it never
ends up in a repository, command line, log file, etc.)



## Command line client

```sh
julia bin/db.jl help
```

These CLI commands are implemented:

- `account`: Display account information
- `get`: Download files
- `ls`: List files
- `mkdir`: Create directory
- `rm`: Delete file or directory



## Programming interface

```Julia
using DropboxSDK
```

These API functions are currently supported; see their respective
documentation:

- `files_create_folder`
- `files_delete`
- `files_download`
- `files_get_metadata`
- `files_list_folder`
- `files_upload`
- `users_get_current_account`
- `users_get_space_usage`

There are also a few local helper functions:

- `calc_content_hash_add!`
- `calc_content_hash_get`
- `calc_content_hash_init`
- `calc_content_hash`
- `get_authorization`
