# Set Environment

## Set Environment goals

Set Environment has following goals:
- To install the minimal baseline set of tools/dependencies to be able to:
    - Run containers (docker)
    - Run VMs
    - Run at a host level our FF agent
- To install the right version of nodejs
- To install certain kinds of environments, beyond the very base one:
    - Agent environment
    - Build environment (build tools)
    - Developer environment (developer tools and default configurations)
        - For developers, to install extended sets of components (depending on the selected environments)
    - Setup the environment to run certain kinds of systems
        - System is a collection of components (typically microservices running in dockers)
- To recursively install any dependencies for the environments (e.g. developer environment depends upon at least a build environment, and that depends upon the baseline environment).
- The "set environment" looks up the information about the environment to install. It hasn't this information hard-coded within the "set environment" project.
        - Example: ideally the "set environment" project gives us docker and nodejs from which we can pass the responsibility to install/configure other environments.
- Trust: based on the kind of the system or environment. It installs the secrets for the selected environment.
- To Install configurations (~/.gitconfig,  VSCode configuration, vim config, etc.)
- Depending on the target environment: to install/uninstall some additional components, for example developers will need development secrets (example ~/.npmrc, development docker repository, ability to talk to "parent" system)
- To provide logged in users with as much as possible useful reusable components / functions / packages / settings. Ideally after installing the "set environment" there should be no need to install anything else for productive work.
- To self-check, detect if the setup is broken (example: someone deleted required files) and be able to self-fix.

## Getting Started

### Installing

In order to use this environment, you need to download this project from github and run installer by teh following commands:
``` 
git clone git@github.com:redwolfsecurity/set_environment.git
cd set_environment
./install
```

### Testing

After installation is complete you should open a new terminal window, so that added initialization would be able to inject "set environment" components into your environment (see your initialization files: ~/.bashrc and ~/.profile).
Now you can run test function "is_set_environment_working".

### Now That You're Done

Once this project is installed, your system now has the tools required to build an Agent on. The ff_bash_functions file is in ff_agent/ff_agent/lib/bash/ff_bash_function and contains functions that are useful for other development projects, such as:

- assert_cd which ensures that a cd command is performed correctly
- assert_clean_exit which makes sure a command exits cleanly and aborts the script if it does not
- many other functions for organizing output which can be viewed by viewing the ff_bash_functions file in this git project

## License

Copyright 2022 RedOki

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
