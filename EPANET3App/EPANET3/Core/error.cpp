/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Licensed under the terms of the MIT License (see the LICENSE file for details).
 *
 */

//////////////////////////////////////////////////////////
// Implementation of the various EPANET error classes.  //
//////////////////////////////////////////////////////////

#include "error.h"
using namespace std;

static const int SystemErrorCodes[] =
{
    101, //OUT_OF_MEMORY,
    102, //NO_NETWORK_DATA,

    103, //HEADLOSS_MODEL_NOT_OPENED,
    104, //DEMAND_MODEL_NOT_OPENED,
    105, //LEAKAGE_MODEL_NOT_OPENED
    106, //QUALITY_MODEL_NOT_OPENED
    107, //MATRIX_SOLVER_NOT_OPENED,

    108, //HYDRAULIC_SOLVER_NOT_OPENED,
    109, //QUALITY_SOLVER_NOT_OPENED,
    110, //HYDRAULICS_SOLVER_FAILURE,
    111, //QUALITY_SOLVER_FAILURE

    112  //SOLVER_NOT_INITIALIZED,
 };

static const char* SystemErrorMsgs[] =
{
    "\n\n*** SYSTEM ERROR 101: OUT OF MEMORY",
    "\n\n*** SYSTEM ERROR 102: NO NETWORK DATA TO ANALYZE",
    "\n\n*** SYSTEM ERROR 103: COULD NOT CREATE A HEAD LOSS MODEL",
    "\n\n*** SYSTEM ERROR 104: COULD NOT CREATE A DEMAND MODEL",
    "\n\n*** SYSTEM ERROR 105: COULD NOT CREATE A LEAKAGE MODEL",
    "\n\n*** SYSTEM ERROR 106: COULD NOT CREATE A QUALITY MODEL",
    "\n\n*** SYSTEM ERROR 107: COULD NOT CREATE A MATRIX SOLVER",
    "\n\n*** SYSTEM ERROR 108: HYDRAULIC SOLVER NOT OPENED",
    "\n\n*** SYSTEM ERROR 109: QUALITY SOLVER NOT OPENED",
    "\n\n*** SYSTEM ERROR 110: HYDRAULIC SOLVER FAILURE",
    "\n\n*** SYSTEM ERROR 111: QUALITY SOLVER FAILURE",
    "\n\n*** SYSTEM ERROR 112: SOLVER NOT INITIALIZED"
};

static const int InputErrorCodes[] =
{
    200, //ERRORS_IN_INPUT_DATA
    201, //CANNOT_CREATE_OBJECT
    202, //TOO_FEW_ITEMS
    203, //INVALID_KEYWORD
    204, //DUPLICATE_ID_NAME
    205, //UNDEFINED_OBJECT
    206, //INVALID_NUMBER
    207, //INVALID_TIME
    208  //UNSPECIFIED
};

static const char* InputErrorMsgs[] =
{
    "\n\n*** INPUT ERROR 200: one or more errors in network input data.",
    "\n\n*** INPUT ERROR 201: cannot create object ",
    "\n\n*** INPUT ERROR 202: too few items ",
    "\n\n*** INPUT ERROR 203: invalid keyword ",
    "\n\n*** INPUT ERROR 204: duplicate ID name ",
    "\n\n*** INPUT ERROR 205: undefined object ",
    "\n\n*** INPUT ERROR 206: invalid number ",
    "\n\n*** INPUT ERROR 207: invalid time ",
    "\n\n*** UNSPECIFIED INPUT ERROR "
};

static const int NetworkErrorCodes[] =
{
    220, //ILLEGAL_VALVE_CONNECTION
    223, //TOO_FEW_NODES
    224, //NO_FIXED_GRADE_NODES
    225, //INVALID_TANK_LEVELS
    226, //NO_PUMP_CURVE
    227, //INVALID_PUMP_CURVE
    230, //INVALID_CURVE_DATA
    231, //INVALID_VOLUME_CURVE
    233  //UNCONNECTED_NODE
};

static const char* NetworkErrorMsgs[] =
{
    "\n\n NETWORK ERROR 220: illegal connection for valve ",
    "\n\n NETWORK ERROR 223: too few nodes in network.",
    "\n\n NETWORK ERROR 224: no fixed grade nodes in network.",
    "\n\n NETWORK ERROR 225: invalid depth limits for tank ",
    "\n\n NETWORK ERROR 226: no pump curve supplied for pump ",
    "\n\n NETWORK ERROR 227: invalid pump curve for pump ",
    "\n\n NETWORK ERROR 230: invalid data for curve ",
    "\n\n NETWORK ERROR 231: invalid volume curve for tank ",
    "\n\n NETWORK ERROR 233: no links connected to node "
};


static const int FileErrorCodes[] =
{
    301, // DUPLICATE_FILE_NAMES
    302, // CANNOT_OPEN_INPUT_FILE
    303, // CANNOT_OPEN_REPORT_FILE
    304, // CANNOT_OPEN_OUTPUT_FILE
    305, // CANNOT_OPEN_HYDRAULICS_FILE
    306, // INCOMPATIBLE_HYDRAULICS_FILE
    307, // CANNOT_READ_HYDRAULICS_FILE
    308, // CANNOT_WRITE_TO_OUTPUT_FILE
    309, // CANNOT_WRITE_TO_REPORT_FILE
    310  // NO_RESULTS_SAVED_TO_REPORT
};

static const char* FileErrorMsgs[] =
{
    "\n\n*** FILE ERROR 301: DUPLICATE FILE NAMES",
    "\n\n*** FILE ERROR 302: CANNOT OPEN INPUT FILE",
    "\n\n*** FILE ERROR 303: CANNOT OPEN REPORT FILE",
    "\n\n*** FILE ERROR 304: CANNOT OPEN OUTPUT FILE",
    "\n\n*** FILE ERROR 305: CANNOT OPEN HYDRAULICS FILE",
    "\n\n*** FILE ERROR 306: INCOMPATIBLE HYDRAULICS FILE",
    "\n\n*** FILE ERROR 307: CANNOT READ HYDRAULICS FILE",
    "\n\n*** FILE ERROR 308: CANNOT WRITE TO OUTPUT FILE",
    "\n\n*** FILE ERROR 309: CANNOT WRITE TO REPORT FILE",
    "\n\n*** FILE ERROR 310: NO RESULTS SAVED TO REPORT"
};

//-----------------------------------------------------------------------------

ENerror::ENerror() : code(0), msg("")
{
}

ENerror::~ENerror()
{
}

//-----------------------------------------------------------------------------

SystemError::SystemError(int type)
{
    if ( type >= 0 && type < SYSTEM_ERROR_LIMIT )
    {
        code = SystemErrorCodes[type];
        msg =  SystemErrorMsgs[type];
    }
}

//-----------------------------------------------------------------------------

InputError::InputError(int type, string token)
{
    if (type < 0 || type >= UNSPECIFIED) type = UNSPECIFIED;
    code = InputErrorCodes[type];
    msg = InputErrorMsgs[type] + token;
}

//-----------------------------------------------------------------------------

NetworkError::NetworkError(int type, string id)
{
    if (type >= 0 && type < NETWORK_ERROR_LIMIT)
    {
        code = NetworkErrorCodes[type];
        msg = NetworkErrorMsgs[type] + id;
    }
}

//-----------------------------------------------------------------------------

FileError::FileError(int type)
{
    if ( type >= 0 && type < FILE_ERROR_LIMIT )
    {
        code = FileErrorCodes[type];
        msg =  FileErrorMsgs[type];
    }
}

//-----------------------------------------------------------------------------

const char* EN_errorMessage(int code)
{
    switch (code)
    {
    case 0:   return "No error.";
    case 101: return "Out of memory.";
    case 102: return "No network data to analyze.";
    case 103: return "Could not create a head loss model.";
    case 104: return "Could not create a demand model.";
    case 105: return "Could not create a leakage model.";
    case 106: return "Could not create a quality model.";
    case 107: return "Could not create a matrix solver.";
    case 108: return "Hydraulic solver not opened.";
    case 109: return "Quality solver not opened.";
    case 110: return "Hydraulic solver failure.";
    case 111: return "Quality solver failure.";
    case 112: return "Solver not initialized.";

    case 200: return "One or more errors in network input data.";
    case 201: return "Cannot create object.";
    case 202: return "Too few input items.";
    case 203: return "Invalid keyword.";
    case 204: return "Duplicate ID name.";
    case 205: return "Undefined object.";
    case 206: return "Invalid numeric value.";
    case 207: return "Invalid time value.";
    case 208: return "Unspecified input error.";

    case 220: return "Illegal valve connection.";
    case 223: return "Too few nodes in network.";
    case 224: return "No fixed grade nodes in network.";
    case 225: return "Invalid depth limits for tank.";
    case 226: return "No pump curve supplied for pump.";
    case 227: return "Invalid pump curve for pump.";
    case 230: return "Invalid data for curve.";
    case 231: return "Invalid volume curve for tank.";
    case 233: return "No links connected to node.";

    case 301: return "Duplicate file names.";
    case 302: return "Cannot open input file.";
    case 303: return "Cannot open report file.";
    case 304: return "Cannot open output file.";
    case 305: return "Cannot open hydraulics file.";
    case 306: return "Incompatible hydraulics file.";
    case 307: return "Cannot read hydraulics file.";
    case 308: return "Cannot write to output file.";
    case 309: return "Cannot write to report file.";
    case 310: return "No results saved to report.";
    default:  return "Unknown EPANET error code.";
    }
}
