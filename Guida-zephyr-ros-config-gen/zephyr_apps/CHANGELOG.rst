^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Changelog for package micro_ros_zephyr_apps
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

4.0.1 (2023-06-06)
------------------
* Micro-ros connection manager on an stm32. Ported to zephyr from the Arduino apps example. (`#61 <https://github.com/micro-ROS/zephyr_apps/issues/61>`_) (`#62 <https://github.com/micro-ROS/zephyr_apps/issues/62>`_)
  (cherry picked from commit dd9eb8a43e8de476c44e126b34c552fc3f4fabb0)
  Co-authored-by: Gerard Sequeira <gsequeira@boston-engineering.com>
* Adjust default_params intialization for cpp compatibility to avoid - Designator member outside agrgregate error, when comiler is cpp. (`#57 <https://github.com/micro-ROS/zephyr_apps/issues/57>`_) (`#59 <https://github.com/micro-ROS/zephyr_apps/issues/59>`_)
  (cherry picked from commit c2f6d2043db205c153a9ef88ddc39dac30bdc2d9)
  Co-authored-by: Gerard Sequeira <gsequeira@boston-engineering.com>
* Add UDP config support. Tested on stm32743zi nucleo. (`#53 <https://github.com/micro-ROS/zephyr_apps/issues/53>`_) (`#56 <https://github.com/micro-ROS/zephyr_apps/issues/56>`_)
  (cherry picked from commit 5929a3a3ea4ca2859e7eb5a18a7b00c29552898f)
  Co-authored-by: Gerard Sequeira <gsequeira@boston-engineering.com>
* Contributors: mergify[bot]

4.0.0 (2022-05-25)
------------------
* Fix include paths (`#52 <https://github.com/micro-ROS/zephyr_apps/issues/52>`_)
* Fix include paths
* Fix include paths (`#51 <https://github.com/micro-ROS/zephyr_apps/issues/51>`_)
* Add Blackpill boards to the compatible demos (`#48 <https://github.com/micro-ROS/zephyr_apps/issues/48>`_) (`#50 <https://github.com/micro-ROS/zephyr_apps/issues/50>`_)
* multichange tool (`#44 <https://github.com/micro-ROS/zephyr_apps/issues/44>`_) (`#46 <https://github.com/micro-ROS/zephyr_apps/issues/46>`_)
* Modify RMW API include (`#38 <https://github.com/micro-ROS/zephyr_apps/issues/38>`_)
* Add comment on how to set the used UART port (`#39 <https://github.com/micro-ROS/zephyr_apps/issues/39>`_)
* Add external transport API (`#34 <https://github.com/micro-ROS/zephyr_apps/issues/34>`_)
* Add issue template
* Update add two ints service app
* Update Zephyr Olimex ToF Sensor app (`#30 <https://github.com/micro-ROS/zephyr_apps/issues/30>`_)
* Initial (`#32 <https://github.com/micro-ROS/zephyr_apps/issues/32>`_)
* Rework demos (`#29 <https://github.com/micro-ROS/zephyr_apps/issues/29>`_)
* Change Panda link to world (`#28 <https://github.com/micro-ROS/zephyr_apps/issues/28>`_)
* Use UNUSED macro from RCLC (`#27 <https://github.com/micro-ROS/zephyr_apps/issues/27>`_)
* Updated position estimator app for ST Discovery (`#26 <https://github.com/micro-ROS/zephyr_apps/issues/26>`_)
* Adjusted CMake paths to use MICROS_ROS_FIRMWARE_DIR (`#25 <https://github.com/micro-ROS/zephyr_apps/issues/25>`_)
* Initial (`#24 <https://github.com/micro-ROS/zephyr_apps/issues/24>`_)
* Removing middleware conf from app meta (`#23 <https://github.com/micro-ROS/zephyr_apps/issues/23>`_)
* Adding nucleo_f7 as a supported board in zephyr apps (`#22 <https://github.com/micro-ROS/zephyr_apps/issues/22>`_)
* Initial changes (`#14 <https://github.com/micro-ROS/zephyr_apps/issues/14>`_)
* fix spin time (`#21 <https://github.com/micro-ROS/zephyr_apps/issues/21>`_)
* Updates for 2.4-rc1 (`#20 <https://github.com/micro-ROS/zephyr_apps/issues/20>`_)
* Updating wifi app for ST disco [EXPERIMENTAL] (`#19 <https://github.com/micro-ROS/zephyr_apps/issues/19>`_)
* Add nucleo_h743zi to int32_publisher and ping_pong apps (`#18 <https://github.com/micro-ROS/zephyr_apps/issues/18>`_)
* Fix USB configuration error (`#17 <https://github.com/micro-ROS/zephyr_apps/issues/17>`_)
* Update README.md
* Update licensing (`#12 <https://github.com/micro-ROS/zephyr_apps/issues/12>`_)
* Fix fifo callback duplication (`#13 <https://github.com/micro-ROS/zephyr_apps/issues/13>`_)
* Add native to int32 publisher
* Release micro-ROS Foxy (`#11 <https://github.com/micro-ROS/zephyr_apps/issues/11>`_)
* Revert "Added Disco wifi sample (`#6 <https://github.com/micro-ROS/zephyr_apps/issues/6>`_)" (`#8 <https://github.com/micro-ROS/zephyr_apps/issues/8>`_)
* Update transport from poll to IRQ (`#9 <https://github.com/micro-ROS/zephyr_apps/issues/9>`_)
* Added Disco wifi sample (`#6 <https://github.com/micro-ROS/zephyr_apps/issues/6>`_)
* Add service example (`#5 <https://github.com/micro-ROS/zephyr_apps/issues/5>`_)
* Zephyr serial transport and nucleo_f401re (`#2 <https://github.com/micro-ROS/zephyr_apps/issues/2>`_)
* Update transport (`#1 <https://github.com/micro-ROS/zephyr_apps/issues/1>`_)
* Style
* Added openmanipulator tof app
* Fix naming
* Added host ping_pong Zephyr app
* Fix pong matching on ping_pong app
* Fix on fast build
* Added host application
* Fixing metas
* Updated app ping_pong
* Rename folder
* Adding ping-pong app
* Zephyr fixes
* Update topic naming
* Updating sensor app for the demo
* Update custom to custom_serial
* fix printf
* Update sensors app
* Updated threads library for cmake
* Using metas instead configuration script
* Added sensor publisher
* App configuration
* Board compatibility
* Updated cmake
* Added tof app
* Apps approach
* Cleaning repos
* Cleaning repo
* Renamed usb transport
* Clean makefile
* Removed olimex board
* Working state
* Working conf
* Leds
* Update
* Initial commit
* Updated with new verbosity feature
* Add plantuml diagrams. (`#1 <https://github.com/micro-ROS/zephyr_apps/issues/1>`_)
* Verbosity
* USB working
* Update defconfig
* Ignoring toolchains
* Added external board
* Updated main app
* Merge branch '1bit_Callback' into zephyr
* Working state
* 1bit callback
* 1 bit callback
* Transport callbacks
* Serial transports
* Cmake
* Added makefile
* Initial commit
* Initial commit
