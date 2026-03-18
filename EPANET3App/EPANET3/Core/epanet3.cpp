/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */

///////////////////////////////////////////////
// Implementation of EPANET 3's API library  //
///////////////'''''///////////////////////////

// TO DO:
// - finish implementing all of the functions declared in EPANET3.H
// - provide a brief comment on what each function does

#include "epanet3.h"
#include "Core/project.h"
#include "Core/datamanager.h"
#include "Core/constants.h"
#include "Core/error.h"
#include "Utilities/utilities.h"
#include "Elements/node.h"
#include "Elements/link.h"
#include "Elements/junction.h"
#include "Elements/tank.h"
#include "Elements/pipe.h"
#include "Elements/pump.h"
#include "Elements/valve.h"

#include <iostream>
#include <iomanip>
#include <time.h>
#include <string>
#include <cstring>

using namespace Epanet;

#define project(p) ((Project *)p)

extern "C" {

//-----------------------------------------------------------------------------

int EN_getVersion(int* version)
{
    *version = VERSION;
    return 0;
}

//-----------------------------------------------------------------------------

int EN_runEpanet(const char* inpFile, const char* rptFile, const char* outFile)
{
    std::cout << "\n... EPANET Version 3.0\n";

    // ... declare a Project variable and an error indicator
    Project p;
    int err = 0;

    // ... initialize execution time clock
    clock_t start_t = clock();

    for (;;)
    {
        // ... open the command line files and load network data
        if ( (err = p.openReport(rptFile)) ) break;
        std::cout << "\n    Reading input file ...";
        if ( (err = p.load(inpFile)) ) break;
        if ( (err = p.openOutput(outFile)) ) break;
        p.writeSummary();

        // ... initialize the solver
        std::cout << "\n    Initializing solver ...";
        if ( (err = p.initSolver(false)) ) break;
        std::cout << "\n    ";

        // ... step through each time period
        int t = 0;
        int tstep = 0;
        do
        {
            std::cout << "\r    Solving network at "                     //r
                << Utilities::getTime(t+tstep) << " hrs ...        ";

            // ... run solver to compute hydraulics
            err = p.runSolver(&t);
            p.writeMsgLog();

            // ... advance solver to next period in time while solving for water quality
            if ( !err ) err = p.advanceSolver(&tstep);
        } while (tstep > 0 && !err );
        break;
    }

    // ... simulation was successful
    if ( !err )
    {
        // ... report execution time
        clock_t end_t = clock();
        double cpu_t = ((double) (end_t - start_t)) / CLOCKS_PER_SEC;
        std::stringstream ss;
        ss << "\n  Simulation completed in ";
        p.writeMsg(ss.str());
        ss.str("");
        if ( cpu_t < 0.001 ) ss << "< 0.001 sec.";
        else ss << std::setprecision(3) << cpu_t << " sec.";
        p.writeMsg(ss.str());

        // ... report simulation results
        std::cout << "\n    Writing report ...                           ";
        err = p.writeReport();
        std::cout << "\n    Simulation completed.                         \n";
        std::cout << "\n... EPANET completed in " << ss.str() << "\n";
    }

    if ( err )
    {
        p.writeMsgLog();
        std::cout << "\n\n    There were errors. See report file for details.\n";
        return err;
    }
    return 0;
}

//-----------------------------------------------------------------------------

EN_Project EN_createProject()
{
    Project* p = new Project();
    return (EN_Project *)p;
}

//-----------------------------------------------------------------------------

int EN_deleteProject(EN_Project p)
{
    delete (Project *)p;
    return 0;
}

//-----------------------------------------------------------------------------

int EN_loadProject(const char* fname, EN_Project p)
{
    return project(p)->load(fname);
}

//-----------------------------------------------------------------------------

int EN_saveProject(const char* fname, EN_Project p)
{
    return project(p)->save(fname);
}

//-----------------------------------------------------------------------------

int EN_clearProject(EN_Project p)
{
    project(p)->clear();
    return 0;
}

//-----------------------------------------------------------------------------

////////////////////////////////////////////////////////////////
//  NOT SURE IF THIS METHOD WORKS CORRECTLY -- NEEDS TESTING  //
////////////////////////////////////////////////////////////////
int EN_cloneProject(EN_Project pClone, EN_Project pSource)
{
    if ( pSource == nullptr || pClone == nullptr ) return 102;
    int err = 0;
    std::string tmpFile;
    if ( Utilities::getTmpFileName(tmpFile) )
    {
        try
        {
            EN_saveProject(tmpFile.c_str(), pSource);
            EN_loadProject(tmpFile.c_str(), pClone);
        }
        catch (ENerror const& e)
        {
	        project(pSource)->writeMsg(e.msg);
            err = e.code;
  	    }
        catch (...)
        {
            err = 208; //Unspecified error
        }
        if ( err > 0 )
        {
            EN_clearProject(pClone);
        }
        remove(tmpFile.c_str());
        return err;
    }
    return 208;
}

//-----------------------------------------------------------------------------

int EN_runProject(EN_Project p)    // <<=============  TO BE COMPLETED
{
    return 0;
}

//-----------------------------------------------------------------------------

int EN_initSolver(int initFlows, EN_Project p)
{
    return project(p)->initSolver(initFlows);
}

//-----------------------------------------------------------------------------

int EN_runSolver(int* t, EN_Project p)
{
    return project(p)->runSolver(t);
}

//-----------------------------------------------------------------------------

int EN_advanceSolver(int *dt, EN_Project p)
{
    return project(p)->advanceSolver(dt);
}

//-----------------------------------------------------------------------------

int EN_openOutputFile(const char* fname, EN_Project p)
{
    return project(p)->openOutput(fname);
}

//-----------------------------------------------------------------------------

int EN_saveOutput(EN_Project p)
{
    return project(p)->saveOutput();
}

//-----------------------------------------------------------------------------

int EN_openReportFile(const char* fname, EN_Project p)
{
    return project(p)->openReport(fname);
}

//-----------------------------------------------------------------------------

int EN_writeReport(EN_Project p)
{
    return project(p)->writeReport();
}

//-----------------------------------------------------------------------------

int EN_writeSummary(EN_Project p)
{
    project(p)->writeSummary();
    return 0;
}

//-----------------------------------------------------------------------------

int EN_writeResults(int t, EN_Project p)
{
    project(p)->writeResults(t);
    return 0;
}

//-----------------------------------------------------------------------------

int EN_writeMsgLog(EN_Project p)
{
    project(p)->writeMsgLog();
    return 0;
}

//-----------------------------------------------------------------------------

int EN_getError(int errcode, char* errmsg, int maxLen, EN_Project p)
{
    (void)p;
    if (errmsg == nullptr || maxLen <= 0) return 208;
    const char* msg = EN_errorMessage(errcode);
    std::strncpy(errmsg, msg, static_cast<size_t>(maxLen - 1));
    errmsg[maxLen - 1] = '\0';
    return 0;
}

//-----------------------------------------------------------------------------

int EN_getCount(int element, int* result, EN_Project p)
{
    return DataManager::getCount(element, result, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeIndex(char* name, int* index, EN_Project p)
{
    return DataManager::getNodeIndex(name, index, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeId(int index, char* id, EN_Project p)
{
    return DataManager::getNodeId(index, id, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeType(int index, int* type, EN_Project p)
{
    return DataManager::getNodeType(index, type, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeValue(int index, int param, double* value, EN_Project p)
{
    return DataManager::getNodeValue(index, param, value, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkIndex(char* name, int* index, EN_Project p)
{
    return DataManager::getLinkIndex(name, index, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkId(int index, char* id, EN_Project p)
{
    return DataManager::getLinkId(index, id, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkType(int index, int* type, EN_Project p)
{
    return DataManager::getLinkType(index, type, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkNodes(int index, int* fromNode, int* toNode, EN_Project p)
{
    return DataManager::getLinkNodes(index, fromNode, toNode,
                                     project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkValue(int index, int param, double* value, EN_Project p)
{
   return DataManager::getLinkValue(index, param, value, project(p)->getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getOption(int optionType, double* value, EN_Project p)
{
    if (value == nullptr) return 208;
    Network* nw = project(p)->getNetwork();
    switch (optionType)
    {
    case EN_TRIALS:         *value = nw->option(Options::MAX_TRIALS); break;
    case EN_ACCURACY:       *value = nw->option(Options::RELATIVE_ACCURACY); break;
    case EN_QUALTOL:        *value = nw->option(Options::QUAL_TOLERANCE); break;
    case EN_EMITEXPON:      *value = nw->option(Options::EMITTER_EXPONENT); break;
    case EN_DEMANDMULT:     *value = nw->option(Options::DEMAND_MULTIPLIER); break;
    case EN_HYDTOL:         *value = nw->option(Options::HEAD_TOLERANCE); break;
    case EN_MINPRESSURE:    *value = nw->option(Options::MINIMUM_PRESSURE); break;
    case EN_MAXPRESSURE:    *value = nw->option(Options::SERVICE_PRESSURE); break;
    case EN_PRESSEXPON:     *value = nw->option(Options::PRESSURE_EXPONENT); break;
    case EN_NETLEAKCOEFF1:  *value = nw->option(Options::LEAKAGE_COEFF1); break;
    case EN_NETLEAKCOEFF2:  *value = nw->option(Options::LEAKAGE_COEFF2); break;
    default: return 203;
    }
    return 0;
}

//-----------------------------------------------------------------------------

int EN_getTimeParam(int param, long* value, EN_Project p)
{
    if (value == nullptr) return 208;
    Network* nw = project(p)->getNetwork();
    long duration = nw->option(Options::TOTAL_DURATION);
    long hydStep = nw->option(Options::HYD_STEP);
    switch (param)
    {
    case EN_DURATION:      *value = duration; break;
    case EN_HYDSTEP:       *value = hydStep; break;
    case EN_QUALSTEP:      *value = nw->option(Options::QUAL_STEP); break;
    case EN_PATTERNSTEP:   *value = nw->option(Options::PATTERN_STEP); break;
    case EN_PATTERNSTART:  *value = nw->option(Options::PATTERN_START); break;
    case EN_REPORTSTEP:    *value = nw->option(Options::REPORT_STEP); break;
    case EN_REPORTSTART:   *value = nw->option(Options::REPORT_START); break;
    case EN_RULESTEP:      *value = nw->option(Options::RULE_STEP); break;
    case EN_STATISTIC:     *value = nw->option(Options::REPORT_STATISTIC); break;
    case EN_PERIODS:
        *value = (hydStep > 0) ? (duration / hydStep + 1) : 0;
        break;
    case EN_STARTDATE:
        *value = 0;   // not tracked in current EPANET3 core
        break;
    default: return 203;
    }
    return 0;
}

//-----------------------------------------------------------------------------

int EN_getFlowUnits(int* value, EN_Project p)
{
    if (value == nullptr) return 208;
    *value = project(p)->getNetwork()->option(Options::FLOW_UNITS);
    return 0;
}

//-----------------------------------------------------------------------------

int EN_setTimeParam(int param, int value, EN_Project p)
{
    Network* nw = project(p)->getNetwork();
    switch (param)
    {
    case EN_DURATION:      nw->options.setOption(Options::TOTAL_DURATION, value); break;
    case EN_HYDSTEP:       nw->options.setOption(Options::HYD_STEP, value); break;
    case EN_QUALSTEP:      nw->options.setOption(Options::QUAL_STEP, value); break;
    case EN_PATTERNSTEP:   nw->options.setOption(Options::PATTERN_STEP, value); break;
    case EN_PATTERNSTART:  nw->options.setOption(Options::PATTERN_START, value); break;
    case EN_REPORTSTEP:    nw->options.setOption(Options::REPORT_STEP, value); break;
    case EN_REPORTSTART:   nw->options.setOption(Options::REPORT_START, value); break;
    case EN_RULESTEP:      nw->options.setOption(Options::RULE_STEP, value); break;
    case EN_STATISTIC:     nw->options.setOption(Options::REPORT_STATISTIC, value); break;
    default: return 203;
    }
    return 0;
}

//-----------------------------------------------------------------------------

int EN_setOption(int optionType, double value, EN_Project p)
{
    Network* nw = project(p)->getNetwork();
    switch (optionType)
    {
    case EN_TRIALS:
        nw->options.setOption(Options::MAX_TRIALS, static_cast<int>(value));
        break;
    case EN_ACCURACY:       nw->options.setOption(Options::RELATIVE_ACCURACY, value); break;
    case EN_QUALTOL:        nw->options.setOption(Options::QUAL_TOLERANCE, value); break;
    case EN_EMITEXPON:      nw->options.setOption(Options::EMITTER_EXPONENT, value); break;
    case EN_DEMANDMULT:     nw->options.setOption(Options::DEMAND_MULTIPLIER, value); break;
    case EN_HYDTOL:         nw->options.setOption(Options::HEAD_TOLERANCE, value); break;
    case EN_MINPRESSURE:    nw->options.setOption(Options::MINIMUM_PRESSURE, value); break;
    case EN_MAXPRESSURE:    nw->options.setOption(Options::SERVICE_PRESSURE, value); break;
    case EN_PRESSEXPON:     nw->options.setOption(Options::PRESSURE_EXPONENT, value); break;
    case EN_NETLEAKCOEFF1:  nw->options.setOption(Options::LEAKAGE_COEFF1, value); break;
    case EN_NETLEAKCOEFF2:  nw->options.setOption(Options::LEAKAGE_COEFF2, value); break;
    default: return 203;
    }
    return 0;
}

//-----------------------------------------------------------------------------

int EN_setNodeValue(int index, int param, double value, EN_Project p)
{
    Network* nw = project(p)->getNetwork();
    if (index < 0 || index >= nw->count(Element::NODE)) return 205;
    Node* node = nw->node(index);
    double lcf = nw->ucf(Units::LENGTH);
    double qcf = nw->ucf(Units::FLOW);
    double ccf = nw->ucf(Units::CONCEN);

    switch (param)
    {
    case EN_ELEVATION:
        node->elev = value / lcf;
        return 0;
    case EN_BASEDEMAND:
        if (node->type() == Node::JUNCTION)
        {
            Junction* j = static_cast<Junction*>(node);
            j->primaryDemand.baseDemand = value / qcf;
            return 0;
        }
        return 203;
    case EN_INITQUAL:
        node->initQual = value / ccf;
        return 0;
    case EN_XCOORD:
        node->xCoord = value;
        return 0;
    case EN_YCOORD:
        node->yCoord = value;
        return 0;
    case EN_TANKLEVEL:
        if (node->type() == Node::TANK)
        {
            Tank* t = static_cast<Tank*>(node);
            t->initHead = t->elev + value / lcf;
            return 0;
        }
        return 203;
    default:
        return 203;
    }
}

//-----------------------------------------------------------------------------

int EN_setLinkValue(int index, int param, double value, EN_Project p)
{
    Network* nw = project(p)->getNetwork();
    if (index < 0 || index >= nw->count(Element::LINK)) return 205;
    Link* link = nw->link(index);
    double lcf = nw->ucf(Units::LENGTH);
    double dcf = nw->ucf(Units::DIAMETER);

    switch (param)
    {
    case EN_DIAMETER:
        link->diameter = value / dcf;
        return 0;
    case EN_MINORLOSS:
        if (value < 0.0) return 206;
        link->lossCoeff = value;
        return 0;
    case EN_INITSTATUS:
        link->initStatus = (value == 0.0) ? Link::LINK_CLOSED : Link::LINK_OPEN;
        return 0;
    case EN_INITSETTING:
        link->initSetting = value;
        return 0;
    case EN_LENGTH:
        if (link->type() == Link::PIPE)
        {
            Pipe* pipe = static_cast<Pipe*>(link);
            if (value <= 0.0) return 206;
            pipe->length = value / lcf;
            return 0;
        }
        return 203;
    case EN_ROUGHNESS:
        if (link->type() == Link::PIPE)
        {
            Pipe* pipe = static_cast<Pipe*>(link);
            if (value <= 0.0) return 206;
            pipe->roughness = value;
            return 0;
        }
        return 203;
    case EN_KBULK:
        if (link->type() == Link::PIPE)
        {
            static_cast<Pipe*>(link)->bulkCoeff = value;
            return 0;
        }
        return 203;
    case EN_KWALL:
        if (link->type() == Link::PIPE)
        {
            static_cast<Pipe*>(link)->wallCoeff = value;
            return 0;
        }
        return 203;
    case EN_LEAKCOEFF1:
        if (link->type() == Link::PIPE)
        {
            static_cast<Pipe*>(link)->leakCoeff1 = value;
            return 0;
        }
        return 203;
    case EN_LEAKCOEFF2:
        if (link->type() == Link::PIPE)
        {
            static_cast<Pipe*>(link)->leakCoeff2 = value;
            return 0;
        }
        return 203;
    default:
        return 203;
    }
}

//-----------------------------------------------------------------------------

int EN_createNode(char* id, int type, EN_Project p)
{
    if (id == nullptr || id[0] == '\0') return 208;
    Network* nw = project(p)->getNetwork();
    std::string name(id);
    if (nw->indexOf(Element::NODE, name) >= 0) return 204;
    if (type < EN_JUNCTION || type > EN_TANK) return 203;
    int subType = Node::JUNCTION;
    if (type == EN_RESERVOIR) subType = Node::RESERVOIR;
    else if (type == EN_TANK) subType = Node::TANK;
    if (!nw->addElement(Element::NODE, subType, name)) return 201;
    return 0;
}

//-----------------------------------------------------------------------------

int EN_createLink(char* id, int type, int fromNode, int toNode, EN_Project p)
{
    if (id == nullptr || id[0] == '\0') return 208;
    Network* nw = project(p)->getNetwork();
    std::string name(id);
    if (nw->indexOf(Element::LINK, name) >= 0) return 204;
    if (fromNode < 0 || fromNode >= nw->count(Element::NODE)) return 205;
    if (toNode < 0 || toNode >= nw->count(Element::NODE)) return 205;
    int subType = Link::PIPE;
    bool isCVPipe = false;
    if (type == EN_CVPIPE) { subType = Link::PIPE; isCVPipe = true; }
    else if (type == EN_PIPE) subType = Link::PIPE;
    else if (type == EN_PUMP) subType = Link::PUMP;
    else if (type >= EN_PRV && type <= EN_GPV) subType = Link::VALVE;
    else return 203;

    if (!nw->addElement(Element::LINK, subType, name)) return 201;
    Link* link = nw->link(nw->count(Element::LINK) - 1);
    link->fromNode = nw->node(fromNode);
    link->toNode = nw->node(toNode);

    if (subType == Link::PIPE && isCVPipe)
    {
        Pipe* pipe = static_cast<Pipe*>(link);
        pipe->hasCheckValve = true;
    }
    if (subType == Link::VALVE)
    {
        Valve* valve = static_cast<Valve*>(link);
        valve->valveType = static_cast<Valve::ValveType>(type - EN_PRV);
    }
    return 0;
}

//-----------------------------------------------------------------------------

int EN_deleteNode(char* id, EN_Project p)
{
    if (id == nullptr || id[0] == '\0') return 208;
    return project(p)->getNetwork()->deleteElement(Element::NODE, std::string(id));
}

//-----------------------------------------------------------------------------

int EN_deleteLink(char* id, EN_Project p)
{
    if (id == nullptr || id[0] == '\0') return 208;
    return project(p)->getNetwork()->deleteElement(Element::LINK, std::string(id));
}


}  // end of namespace
