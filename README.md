# Set Environment

This project will generate the environment in which a Agent will be initialized, providing the programs and tools for deployment

These currently include:
- Docker
- C++ Compiler Tools
- Automake
- nodeJS
- NPM
- Grunt


This project also contains functions and variables files that are needed to install any other parts of the Agent.

This must be installed before any other parts of the Agent stack are.

## Getting Started

In order to use this environment, you need only check out this project and run the **install.sh** script.

### Prerequisites

- In order to use this project, you will need to have git so you can clone this project. you can install git by using the following command:
```bash
sudo apt-get install git
```
- The Build Environment is designed to run on Ubuntu
- Make sure you have root permissions before starting this installation
- Make sure you have CONTENT_URL environment defined, which points to the web server (to download some of bootstrap content)

### Installing

To install this project, you must start by navigating to the directory in which you would like to place it.

Next you need to check out this project:
```
git clone https://<username>@github.com/redoki/build_environment .
```
where <username> is the username you wish to use to check out the project

you will now be prompted to enter the password for the account you chose and when the authentication is finished, the project will be in your current directory

:warning: DO NOT INSTALL THIS SCRIPT AS **root** USER

Once you have successfully cloned the project, run the build script with the following command
```
bash install.sh
```

## Testing

This project currently only implements self testing, the tests are performed on startup and if it succeeds in installing all of the programs then it has cleared all tests

## Now That You're Done

Once this project is installed, your system now has the tools required to build an Agent on. The ff_bash_functions file is in /usr/local/bin and contains functions that are useful for other development projects, such as:

- assert_cd which ensures that a cd command is performed correctly
- assert_clean_exit which makes sure a command exits cleanly and aborts the script if it does not
- many other functions for organizing output which can be viewed by viewing the ff_bash_functions file in this git project


## License

Copyright 2021 RedOki

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
