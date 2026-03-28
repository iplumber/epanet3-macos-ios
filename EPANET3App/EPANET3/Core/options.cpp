/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Licensed under the terms of the MIT License (see the LICENSE file for details).
 *
 */

 /////////////////////////////////////////////
 //  Implementation of the Options class.  //
 ////////////////////////////////////////////

#include "options.h"
#include "network.h"
#include "constants.h"
#include "error.h"
#include "Elements/element.h"
#include "Elements/pattern.h"
#include "Models/qualmodel.h"
#include "Utilities/utilities.h"

#include <iostream>

#include <stdlib.h>
#include <iomanip>
#include <algorithm>
using namespace std;

//-----------------------------------------------------------------------------

// Keywords for FlowUnits enumeration in options.h
static const char* flowUnitsWords[] =
    {"CFS", "GPM", "MGD", "IMGD", "AFD", "LPS", "LPM", "MLD", "CMH", "CMD", 0};

// Keywords for PressureUnits enumeration in options.h
static const char* pressureUnitsWords[] = {"PSI", "METERS", "PKA", 0};

// Headloss formula keywords
static const char* headlossModelWords[] = {"H-W", "D-W", "C-M", 0};

// Hydraulic Newton solver step size method names
static const char* stepSizingWords[] = {"FULL", "RELAXATION", "LINESEARCH", 0};

static const char* ifUnbalancedWords[] = {"STOP", "CONTINUE", 0};

// Demand model keywords
static const char* demandModelWords[] =
    {"FIXED", "CONSTRAINED", "POWER", "LOGISTIC", 0};

// Leakage model keywords
static const char* leakageModelWords[] =
    {"NONE", "POWER", "FAVAD", 0};

// Quality model keywords
static const char* qualModelWords[] = {"NONE", "AGE", "TRACE", "CHEMICAL", 0};

// Quality units keywords
static const char* qualUnitsWords[] = {"", "HRS", "PCNT", "MG/L", "UG/L", 0};

// File mode keywords
//static const char* w_Use  = "USE";
//static const char* w_Save = "SAVE";

//-----------------------------------------------------------------------------

Options::Options()
{
    setDefaults();
}

//-----------------------------------------------------------------------------

void Options::setDefaults()
{
    outputFracDigits                       = 4;
    stringOptions[HYD_FILE_NAME]           = "";
    stringOptions[OUT_FILE_NAME]           = "";
    stringOptions[RPT_FILE_NAME]           = "";
    stringOptions[MAP_FILE_NAME]           = "";
    stringOptions[HEADLOSS_MODEL]          = "H-W";
    stringOptions[DEMAND_MODEL]            = "FIXED";

    stringOptions[LEAKAGE_MODEL]           = "NONE";
    stringOptions[HYD_SOLVER]              = "GGA";
    stringOptions[STEP_SIZING]             = "FULL";
    stringOptions[MATRIX_SOLVER]           = "SPARSPAK";
    stringOptions[DEMAND_PATTERN_NAME]     = "";
    stringOptions[QUAL_MODEL]              = "NONE";
    stringOptions[QUAL_NAME]               = "Chemical";
    stringOptions[QUAL_UNITS_NAME]         = "MG/L";
    stringOptions[TRACE_NODE_NAME]         = "";

    indexOptions[UNIT_SYSTEM]              = US;
    indexOptions[FLOW_UNITS]               = GPM;
    indexOptions[PRESSURE_UNITS]           = PSI;
    indexOptions[MAX_TRIALS]               = 100;
    indexOptions[IF_UNBALANCED]            = STOP;
    indexOptions[HYD_FILE_MODE]            = SCRATCH;
    indexOptions[DEMAND_PATTERN]           = -1;
    indexOptions[ENERGY_PRICE_PATTERN]     = -1;
    indexOptions[QUAL_TYPE]                = NOQUAL;
    indexOptions[QUAL_UNITS]               = MGL;
    indexOptions[TRACE_NODE]               = -1;

    indexOptions[REPORT_SUMMARY]           = true;
    indexOptions[REPORT_ENERGY]            = false;
    indexOptions[REPORT_STATUS]            = false;
    indexOptions[REPORT_TRIALS]            = false;
    indexOptions[REPORT_NODES]             = NONE;
    indexOptions[REPORT_LINKS]             = NONE;

    valueOptions[MINIMUM_PRESSURE]         = 0.0;
    valueOptions[SERVICE_PRESSURE]         = 0.0;
    valueOptions[PRESSURE_EXPONENT]        = 0.5;
    valueOptions[EMITTER_EXPONENT]         = 0.5;
    valueOptions[DEMAND_MULTIPLIER]        = 1.0;

    valueOptions[RELATIVE_ACCURACY]        = 0.0;
    valueOptions[HEAD_TOLERANCE]           = 0.0;
    valueOptions[FLOW_TOLERANCE]           = 0.0;
    valueOptions[FLOW_CHANGE_LIMIT]        = 0.0;
    valueOptions[TIME_WEIGHT]              = 0.0;

    valueOptions[ENERGY_PRICE]             = 0.0;
    valueOptions[PEAKING_CHARGE]           = 0.0;
    valueOptions[PUMP_EFFICIENCY]          = 0.75;
    valueOptions[SPEC_GRAVITY]             = 1.0;
    valueOptions[KIN_VISCOSITY]            = VISCOSITY;
    valueOptions[MOLEC_DIFFUSIVITY]        = DIFFUSIVITY;
    valueOptions[QUAL_TOLERANCE]           = 0.01;
    valueOptions[BULK_ORDER]               = 1.0;
    valueOptions[WALL_ORDER]               = 1.0;
    valueOptions[TANK_ORDER]               = 1.0;
    valueOptions[BULK_COEFF]               = 0.0;
    valueOptions[WALL_COEFF]               = 0.0;
    valueOptions[LIMITING_CONCEN]          = 0.0;
    valueOptions[ROUGHNESS_FACTOR]         = 0.0;

    valueOptions[LEAKAGE_COEFF1]           = 0.0;
    valueOptions[LEAKAGE_COEFF2]           = 0.0;

    timeOptions[START_TIME]                = 0;
    timeOptions[HYD_STEP]                  = 3600;
    timeOptions[QUAL_STEP]                 = 300;
    timeOptions[PATTERN_STEP]              = 3600;
    timeOptions[PATTERN_START]             = 0;
    timeOptions[REPORT_STEP]               = 3600;
    timeOptions[REPORT_START]              = 0;
    timeOptions[RULE_STEP]                 = 300;
    timeOptions[TOTAL_DURATION]            = 0;

    reportFields.setDefaults();
}

//-----------------------------------------------------------------------------

int Options::setOption(StringOption option, const string& value)
{
    int i;
    switch (option)
    {
    case HEADLOSS_MODEL:
        i = Utilities::findFullMatch(value, headlossModelWords);
        if (i < 0) return InputError::INVALID_KEYWORD;
        stringOptions[HEADLOSS_MODEL] = headlossModelWords[i];
        break;

    case STEP_SIZING:
        i = Utilities::findFullMatch(value, stepSizingWords);
        if (i < 0) return InputError::INVALID_KEYWORD;
        stringOptions[STEP_SIZING] = stepSizingWords[i];
        break;

    case DEMAND_MODEL:
        i = Utilities::findFullMatch(value, demandModelWords);
        if (i < 0) return InputError::INVALID_KEYWORD;
        stringOptions[DEMAND_MODEL] = demandModelWords[i];
        break;

    case LEAKAGE_MODEL:
        i = Utilities::findFullMatch(value, leakageModelWords);
        if (i < 0) return InputError::INVALID_KEYWORD;
        stringOptions[LEAKAGE_MODEL] = leakageModelWords[i];
        break;

    case QUAL_MODEL:
        i = Utilities::findFullMatch(value, qualModelWords);
        if ( i < 0 )
        {
            stringOptions[QUAL_MODEL] = "CHEMICAL";
            stringOptions[QUAL_NAME]  = value;
            indexOptions[QUAL_TYPE]   = CHEM;
            indexOptions[QUAL_UNITS]  = MGL;
        }
        else
        {
            stringOptions[QUAL_MODEL] = qualModelWords[i];
            indexOptions[QUAL_TYPE]   = i;
            if ( indexOptions[QUAL_TYPE] != CHEM )
            {
                stringOptions[QUAL_NAME]  = qualModelWords[i];
                indexOptions[QUAL_UNITS]  = i;
            }
	    }
        break;

    case QUAL_NAME:
        stringOptions[QUAL_NAME]  = value;
        break;

    case QUAL_UNITS_NAME:
        i = Utilities::findFullMatch(value, qualUnitsWords);
        if (i < 0) return InputError::INVALID_KEYWORD;;
        if ( i == MGL || i == UGL ) indexOptions[QUAL_UNITS] = i;
        break;

    case TRACE_NODE_NAME:
        stringOptions[TRACE_NODE_NAME] = value;
        break;

    default: break;
    }
    return 0;
}

//-----------------------------------------------------------------------------

void Options::setOption(IndexOption option, int value)
{
    indexOptions[option] = value;
}

int Options::setOption(IndexOption option, const string& value, Network* network)
{
    int i;
    string ucValue = Utilities::upperCase(value);
    switch (option)
    {
    case FLOW_UNITS:
        i = Utilities::findFullMatch(ucValue, flowUnitsWords);
        if ( i < 0 ) return InputError::INVALID_KEYWORD;
        indexOptions[FLOW_UNITS] = i;
        break;

    case PRESSURE_UNITS:
        i = Utilities::findFullMatch(ucValue, pressureUnitsWords);
        if ( i < 0 ) return InputError::INVALID_KEYWORD;
        indexOptions[PRESSURE_UNITS] = i;
        break;

    case MAX_TRIALS:
        i = atoi(value.c_str());
        if ( i <= 0 ) return InputError::INVALID_NUMBER;
        indexOptions[MAX_TRIALS] = i;
        break;

    case IF_UNBALANCED:
        i = Utilities::findFullMatch(ucValue, ifUnbalancedWords);
        if ( i < 0 ) return InputError::INVALID_KEYWORD;
        indexOptions[IF_UNBALANCED] = i;
        break;

    case HYD_FILE_MODE: break;

    case DEMAND_PATTERN:
        i = network->indexOf(Element::PATTERN, value);
        if ( i >= 0 )
        {
            indexOptions[DEMAND_PATTERN] = i;
            stringOptions[DEMAND_PATTERN_NAME] = value;
        }
        break;

    case TRACE_NODE:
        i = network->indexOf(Element::NODE, value);
        if (i < 0) return InputError::UNDEFINED_OBJECT;
        indexOptions[TRACE_NODE] = i;
        stringOptions[TRACE_NODE_NAME] = value;
        break;

    default: break;
    }
    return 0;
}

//-----------------------------------------------------------------------------

void Options::setOption(ValueOption option, double value)
{
    if ( option == KIN_VISCOSITY && value > 1.0e-3 ) value *= VISCOSITY;
    if ( option == MOLEC_DIFFUSIVITY && value > 1.0e-3 ) value *= DIFFUSIVITY;
    valueOptions[option] = value;
}

//-----------------------------------------------------------------------------

void Options::setOption(TimeOption option, int value)
{
    timeOptions[option] = value;
}

//-----------------------------------------------------------------------------

void Options::setReportFieldOption(int type,
                                   int index,
                                   int enabled,
                                   int precision,
                                   double lowerLimit,
                                   double upperLimit)
{
    reportFields.setField(type, index, enabled, precision, lowerLimit, upperLimit);
}

//-----------------------------------------------------------------------------

void Options::adjustOptions()
{
    // ... report start time cannot be greater than simulation duration */
    if ( timeOptions[REPORT_START] > timeOptions[TOTAL_DURATION] )
    {
        timeOptions[REPORT_START] = 0;
    }

    // ... no water quality analysis for steady state run
    if ( timeOptions[TOTAL_DURATION] == 0 ) indexOptions[QUAL_TYPE] = NOQUAL;

    // ... quality timestep cannot be greater than hydraulic timestep
    timeOptions[QUAL_STEP] = min(timeOptions[QUAL_STEP], timeOptions[HYD_STEP]);

    // ... rule time step cannot be greater than hydraulic time step
    timeOptions[RULE_STEP] = min(timeOptions[RULE_STEP], timeOptions[HYD_STEP]);

    // ... make REPORT_STATUS true if REPORT_TRIALS is true
    if ( indexOptions[REPORT_TRIALS] == true ) indexOptions[REPORT_STATUS] = true;
}

//-----------------------------------------------------------------------------

string Options::epanet2OptionsToStr(Network* network)
{
    // Field names and order follow EPANET 2.x / typical net1.inp [OPTIONS] for EPANET 2.2 compatibility.
    const int w = 19;
    stringstream s;
    s << left;

    s << setw(w) << "Units" << flowUnitsWords[indexOptions[FLOW_UNITS]] << "\n";
    s << setw(w) << "Headloss" << stringOptions[HEADLOSS_MODEL] << "\n";
    s << setw(w) << "Specific Gravity" << Utilities::inpDoubleToStr(valueOptions[SPEC_GRAVITY]) << "\n";
    s << setw(w) << "Viscosity" << Utilities::inpDoubleToStr(valueOptions[KIN_VISCOSITY] / VISCOSITY) << "\n";
    s << setw(w) << "Trials" << indexOptions[MAX_TRIALS] << "\n";

    double accuracy = valueOptions[RELATIVE_ACCURACY];
    if ( accuracy <= 0.0 ) accuracy = valueOptions[HEAD_TOLERANCE];
    if ( accuracy <= 0.0 ) accuracy = 0.001;
    s << setw(w) << "Accuracy" << Utilities::inpDoubleToStr(accuracy) << "\n";

    s << setw(w) << "CHECKFREQ" << "2" << "\n";
    s << setw(w) << "MAXCHECK" << "10" << "\n";
    s << setw(w) << "DAMPLIMIT" << Utilities::inpDoubleToStr(0.0) << "\n";

    // Compare numeric values (IfUnbalanced::CONTINUE) — avoid Windows CONTINUE macro clash.
    if ( indexOptions[IF_UNBALANCED] != 0 )
        s << setw(w) << "Unbalanced" << "Continue 10" << "\n";
    else
        s << setw(w) << "Unbalanced" << "Stop" << "\n";

    string patName = stringOptions[DEMAND_PATTERN_NAME];
    if ( patName.empty() && network && network->count(Element::PATTERN) > 0 )
        patName = network->pattern(0)->name;
    if ( patName.empty() ) patName = "1";
    s << setw(w) << "Pattern" << patName << "\n";

    s << setw(w) << "Demand Multiplier" << Utilities::inpDoubleToStr(valueOptions[DEMAND_MULTIPLIER]) << "\n";
    s << setw(w) << "Emitter Exponent" << Utilities::inpDoubleToStr(valueOptions[EMITTER_EXPONENT]) << "\n";

    string qualVal;
    switch ( indexOptions[QUAL_TYPE] )
    {
    case NOQUAL:
        qualVal = "NONE";
        break;
    case AGE:
        qualVal = "Age";
        break;
    case TRACE:
        qualVal = string("Trace ") + stringOptions[TRACE_NODE_NAME];
        break;
    case CHEM:
    default:
        {
            string units = "mg/L";
            if ( indexOptions[QUAL_UNITS] == UGL ) units = "ug/L";
            else if ( indexOptions[QUAL_UNITS] == MGL ) units = "mg/L";
            qualVal = stringOptions[QUAL_NAME] + " " + units;
        }
        break;
    }
    s << setw(w) << "Quality" << qualVal << "\n";

    s << setw(w) << "Diffusivity" << Utilities::inpDoubleToStr(valueOptions[MOLEC_DIFFUSIVITY] / DIFFUSIVITY) << "\n";
    s << setw(w) << "Tolerance" << Utilities::inpDoubleToStr(valueOptions[QUAL_TOLERANCE]) << "\n";
    return s.str();
}

//-----------------------------------------------------------------------------

string Options::energyOptionsToStr(Network* network)
{
    int w = 26;
    stringstream s;
    s << left;
    s << setw(w) << "GLOBAL EFFICIENCY ";
    s << Utilities::inpDoubleToStr(valueOptions[PUMP_EFFICIENCY]) << "\n";
    s << setw(w) << "GLOBAL PRICE";
    s << Utilities::inpDoubleToStr(valueOptions[ENERGY_PRICE]) << "\n";
    int p = indexOptions[ENERGY_PRICE_PATTERN];
    if (p >= 0)
    {
        s << setw(w) << "GLOBAL PATTERN";
        s << network->pattern(p)->name << "\n";
    }
    s << setw(w) << "DEMAND CHARGE";
    s << Utilities::inpDoubleToStr(valueOptions[PEAKING_CHARGE]) << "\n";
    return s.str();
}

//-----------------------------------------------------------------------------

string Options::reactOptionsToStr()
{
    int w = 26;
    stringstream s;
    s << left;
    s << setw(w) << "ORDER BULK" << Utilities::inpDoubleToStr(valueOptions[BULK_ORDER]) << "\n";
    s << setw(w) << "ORDER WALL" << Utilities::inpDoubleToStr(valueOptions[WALL_ORDER]) << "\n";
    s << setw(w) << "ORDER TANK" << Utilities::inpDoubleToStr(valueOptions[TANK_ORDER]) << "\n";
    s << setw(w) << "GLOBAL BULK" << Utilities::inpDoubleToStr(valueOptions[BULK_COEFF]) << "\n";
    s << setw(w) << "GLOBAL WALL" << Utilities::inpDoubleToStr(valueOptions[WALL_COEFF]) << "\n";
    s << setw(w) << "LIMITING POTENTIAL" <<
        Utilities::inpDoubleToStr(valueOptions[LIMITING_CONCEN]) << "\n";
    s << setw(w) << "ROUGHNESS CORRELATION" <<
        Utilities::inpDoubleToStr(valueOptions[ROUGHNESS_FACTOR]) << "\n";
    return s.str();
}

//-----------------------------------------------------------------------------

string Options::epanet2TimeOptionsToStr()
{
    int w = 26;
    stringstream s;
    s << left;
    // EPANET 2.2 timedata() expects DURATION (not TOTAL DURATION), etc. (see EPANET2.2 SRC_engines/input3.c timedata).
    s << setw(w) << "Duration" <<
        Utilities::getTime(timeOptions[TOTAL_DURATION]) << "\n";
    s << setw(w) << "Hydraulic Timestep" <<
        Utilities::getTime(timeOptions[HYD_STEP]) << "\n";
    s << setw(w) << "Quality Timestep" <<
        Utilities::getTime(timeOptions[QUAL_STEP]) << "\n";
    s << setw(w) << "Rule Timestep" <<
        Utilities::getTime(timeOptions[RULE_STEP]) << "\n";
    s << setw(w) << "Pattern Timestep" <<
        Utilities::getTime(timeOptions[PATTERN_STEP]) << "\n";
    s << setw(w) << "Pattern Start" <<
        Utilities::getTime(timeOptions[PATTERN_START]) << "\n";
    s << setw(w) << "Report Timestep" <<
        Utilities::getTime(timeOptions[REPORT_STEP]) << "\n";
    s << setw(w) << "Report Start" <<
        Utilities::getTime(timeOptions[REPORT_START]) << "\n";
    s << setw(w) << "Start ClockTime" <<
        Utilities::getTime(timeOptions[START_TIME]) << "\n";
    s << setw(w) << "Statistic" << "None\n";
    return s.str();
}

//-----------------------------------------------------------------------------

string Options::timeOptionsToStr()
{
    int w = 26;
    stringstream s;
    s << left;
    s << setw(w) << "TOTAL DURATION" <<
        Utilities::getTime(timeOptions[TOTAL_DURATION]) << "\n";
    s << setw(w) << "HYDRAULIC TIMESTEP" <<
        Utilities::getTime(timeOptions[HYD_STEP]) << "\n";
    s << setw(w) << "QUALITY TIMESTEP" <<
        Utilities::getTime(timeOptions[QUAL_STEP]) << "\n";
    s << setw(w) << "RULE TIMESTEP" <<
        Utilities::getTime(timeOptions[RULE_STEP]) << "\n";
    s << setw(w) << "PATTERN TIMESTEP" <<
        Utilities::getTime(timeOptions[PATTERN_STEP]) << "\n";
    s << setw(w) << "PATTERN START" <<
        Utilities::getTime(timeOptions[PATTERN_START]) << "\n";
    s << setw(w) << "REPORT TIMESTEP" <<
        Utilities::getTime(timeOptions[REPORT_STEP]) << "\n";
    s << setw(w) << "REPORT START" <<
        Utilities::getTime(timeOptions[REPORT_START]) << "\n";
    s << setw(w) << "START CLOCKTIME" <<
        Utilities::getTime(timeOptions[START_TIME]) << "\n";
    return s.str();
}

//-----------------------------------------------------------------------------

string Options::reportOptionsToStr()
{
    int w = 26;
    stringstream s;
    s << left;
    if ( indexOptions[REPORT_SUMMARY] )
        s << setw(w) << "SUMMARY" << "YES\n";
    if ( indexOptions[REPORT_ENERGY] )
        s << setw(w) << "ENERGY" << "YES\n";
    if ( indexOptions[REPORT_STATUS] )
        s << setw(w) << "STATUS" << "YES\n";
    if ( indexOptions[REPORT_TRIALS] )
        s << setw(w) << "TRIALS" << "YES\n";
    if ( indexOptions[REPORT_NODES] == 1 )
        s << setw(w) << "NODES" << "ALL\n";
    if ( indexOptions[REPORT_LINKS] == 1 )
        s << setw(w) << "LINKS" << "ALL\n";
    if ( stringOptions[RPT_FILE_NAME].length() > 0 )
        s << setw(w) << "FILE" << stringOptions[RPT_FILE_NAME] << "\n";
    return s.str();
}
