cmake_minimum_required(VERSION 3.8)
project(px4_sim)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(ament_cmake_python REQUIRED)

ament_python_install_package(${PROJECT_NAME})

set(PX4_PREBUILT_DIR
    ${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/px4_sitl_default)

# Проверяем, что бинарник действительно лежит в пакете
if(NOT EXISTS "${PX4_PREBUILT_DIR}/bin/px4")
  message(FATAL_ERROR
    "Prebuilt PX4 not found: ${PX4_PREBUILT_DIR}/bin/px4"
  )
endif()

install(
  DIRECTORY
    ${PX4_PREBUILT_DIR}/bin
    ${PX4_PREBUILT_DIR}/etc
  DESTINATION share/${PROJECT_NAME}
  USE_SOURCE_PERMISSIONS
)

ament_environment_hooks(cmake/99_setup.sh.in)

ament_package()