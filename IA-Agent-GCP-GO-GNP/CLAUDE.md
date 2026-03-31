# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope

This project is intended to:

    - Create an IA Agent capable of executing TASK and CTASK from GNP Service Now

    Agent skills shoul be as follows:

1. Be able to execute IAM related tickets
2. Be able to secret administration tickets
3. Be able to execute GKE secrets administration tickets
4. Be able to execute GCP Pub/Sub Administration tickets
5. Be able to create IAM and GKE Service Account Administration tickets

## Instructions for Claude

1. Keep token usage at minimum while maintaining accuracy and precision
2. Do not generate unrequested documentation
3. Keep responses concise and accurate
4. Keep output at minimum while maintaining clarity
5. Always prefere Golang and Bash over Python
6. If solution is not feasible in Golang or Bash, use Python as sparsely as you could
7. The agent should be able to run from a gcp terminal as an executable file

## Permissions

    1. Execute basic Linux/Unix/BSD commands
