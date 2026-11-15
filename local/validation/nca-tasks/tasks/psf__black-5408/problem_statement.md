Github action could return number of changed/formatted files
**Is your feature request related to a problem? Please describe.**

The official psf/black GitHub Action does not seem to return information on its run. Other related actions such as https://github.com/rickstaa/action-black returned an is_formatted flag which could be used by subsequent steps.

If you use an "open pull request" action after the formatting step, and if black did format any file, then you can automatically open a pull request and when approved the formatted code would be committed to the original branch.

Without such a parameter if you queue an "open a pull request" github action after a "format with black" action, you would ALWAYS have a pull request, even if no files had been changed

**Describe the solution you'd like**

Have psf/black return a status or a number of files it changed.

**Describe alternatives you've considered**

none

**Additional context**

Sample workflow in github actions:

```
name: Formatting

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  black:
    runs-on: ubuntu-latest
    name: Format python
    
    steps:
    - name: Check out
      uses: actions/checkout@v3

    - name: Set up Python 3.10
      uses: actions/setup-python@v4
      with:
        python-version: "3.10"

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install black autopep8 isort
        if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

    - name: Format with black
      id: action_black
      uses: psf/black@stable
      with:
        options: "--verbose"
        src: "./src"

    - name: Create Pull Request
      uses: peter-evans/create-pull-request@v4
      with:
        title: "Format Python code with psf/black push"
        commit-message: "Format Python code with psf/black"
        body: "Format Python code with psf/black"
        base: main
        branch: black-format-github-action
        delete-branch: true

```

