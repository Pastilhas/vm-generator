# VM generator

## Overview

This tool was built to be used in ML servers with the purpose of partitioning resources into independent
virtual machines. Users can develop and execute separate projects in controlled environment, while minimizing
waste of resources. The files in this repository serve to create, manage, and destroy virtual machines.

## How it works

An app created in Power Apps allows users to choose the resources they need: number CPUs and GPUs, and
amount of RAM and storage. The request is stored in a SharePoint list, which is then retrieved by a python
script. The script analyses the data and chooses what machines to create or destroy, and runs the
appropriate bash scripts with the correct arguments. The bash scripts are written to be robust against
improper use of the tool, cleaning any traces of the virtual machines when destroyed or malformed.

### Virtual machines

The machines created are running the Ubuntu Server 22.04 LTS, useful for software development and machine
learning purposes.

## Future work

> *As any work it needs improvement -Anon, 1912*

### Dynamic configuration

Currently, the specifications of the system are manually written into multiple files. One improvement to make
to the system would be to centralize this information into a single file. This file could possibly be automatically
created and updated when the server suffers hardware modification.

### Local deployment

The tool was built with the end user interface on Power Apps and using Sharepoint as a middleware. This was due to
the easy integration with Microsoft Teams, and simple implementation with drag-and-drop components and compact coding.
However, these external tools could be substituted by a more personalized custom-made webpage which communicates
directly with the backend system. This would reduce delay from polling Sharepoint at regular intervals. Moreover,
it would remove the reliance on external tools, which would enable a more free software.
