## OLD 

This is a list of steps to insert a new component to build (such as QEMU, BUILDROOT, ATF etc...)

1) CREATE THE NEW COMPILING SCRIPT
    - Manually clone the repository of the new component and compile it in one of the available environment directory -> environment/<target>/<backend>/build/. Once it is done save the specific compilation flags and the specific repository,branch and commit you used for later. 
    - Modify scripts/common/create_new_backend.sh to add all the paths for compiling the new component and retrieving the resulting image (as it is done for all the other components)
    - create a scripts/compile/<name_component>_compile.sh script that simply receive the target as input, compile the new component using the path you inserted in the other scripts and copy the results image (if needed) in the right directory of the target (output or boot)

try the script and verify that the new component output image is generated and copied correcty in the target directory you choose. 

2) UPDATE TARGET CONFIGURATIONS
    - Modify the configuration script of the target you are using (environment/<target>/<backend>/environment_cfgs/<target>-<backend>.sh) and add the following: 
    - in the "## COMPONENTS ##" add:
      - # <name_component> 
      - <name_component>_BUILD="y"
      - <name_component>_COMPILE_ARGS="" 
      - <name_component>_PATCH="" 
      - <name_component>_REPOSITORY=<repository new component>       
      - <name_component>_BRANCH=<branch new component>      
      - <name_component>_COMMIT=<commit new component>   
    
    - In all the other existring targets configuration files (e.g. kria, qemu)
    - in the "## COMPONENTS ##" add:
      - # <NEW COMPONENT> 
      - <name_component>_BUILD="n"

    - In the scripts/common/common.sh script add default component in "# To Build (Default="n")" section:
      - <name_component>_BUILD="n"

3) UPDATE BUILD ENVIRONMENT 
    - In the scripts/build_environment.sh
    - in the "## CLONE PHASE ##" add a new CLONE copying one of the existing and changing the subject 
    - In the "#Wait for all the clones to complete" section add the wait ${pid<name of the component>}
    - in the "## COMPILING PHASE ##" section add a call to the script created in point 1:

4) UPDATE SCRIPT TO CREATE NEW TARGET
  - Modify the script scripts/common/create_new_backend.sh and add the following:
    - in the "## DEFAULT VALUES ##" add the default values copying another configuration
    - in the "## Components configuration" add a new section for the added component following as example one of the others:

5) TEST IT: 
  - deleted the entire directory of the previously created component in environment/<target>/<backend>/build/<name_component>
  - put to "n" to all the "<component>_BUILD" variables in environment/<target>/<backend>/environment_cfgs/<target>-<backend>.sh of your target except for the <component_to_test>_BUILD="y" (remember to save the current configuration to recopy it after the test) 
  - launch ./build_environment.sh -t <target> -b <backend> and verify that the repository is cloned correctly and that the resulting image has been correctly copied in the target directory where expected.

6) [OPTIONAL] Add a configuration managment (to do ...)
