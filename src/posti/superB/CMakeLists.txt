# =========================================================================
# superB
# =========================================================================
SET(TOOL_NAME "superB")
SET(TOOL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/posti/superB")

MESSAGE(STATUS "Posti: building ${TOOL_NAME} tool")
INCLUDE_DIRECTORIES( ${TOOL_DIR})

FILE(GLOB ${TOOL_NAME}F90 ${TOOL_DIR}/CMakeLists.txt
                          ${TOOL_DIR}/*.f90)

ADD_LIBRARY(${TOOL_NAME}libF90 OBJECT ${${TOOL_NAME}F90})
SET_TARGET_PROPERTIES(${TOOL_NAME}libF90 PROPERTIES COMPILE_FLAGS ${PICLAS_COMPILE_FLAGS})
ADD_LIBRARY(${TOOL_NAME}lib STATIC $<TARGET_OBJECTS:${TOOL_NAME}libF90>)
ADD_DEPENDENCIES(${TOOL_NAME}libF90 libpiclasshared)

# Standalone superB executable
add_exec(             ${TOOL_NAME} ${TOOL_DIR}/superB.f90)
TARGET_LINK_LIBRARIES(${TOOL_NAME} ${TOOL_NAME}lib libpiclasshared)
ADD_DEPENDENCIES(     ${TOOL_NAME} ${TOOL_NAME}lib libpiclasshared)

