/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Licensed under the terms of the MIT License (see the LICENSE file for details).
 *
 */

#include "projectwriter.h"
#include "Core/network.h"
#include "Core/options.h"
#include "Core/constants.h"
#include "Core/error.h"
#include "Elements/node.h"
#include "Elements/junction.h"
#include "Elements/reservoir.h"
#include "Elements/tank.h"
#include "Elements/pipe.h"
#include "Elements/pump.h"
#include "Elements/valve.h"
#include "Elements/pattern.h"
#include "Elements/curve.h"
#include "Elements/pattern.h"
#include "Elements/control.h"
#include "Elements/emitter.h"
#include "Elements/qualsource.h"
#include "Utilities/utilities.h"

#include <cmath>
#include <iomanip>
#include <string>
using namespace std;

namespace {

/// EPANET INP-style numeric cell: integers without decimals; otherwise up to `maxFracDigits` fractional digits.
void writeInpIntOrFrac(ostream& out, int width, double v, int maxFracDigits)
{
    ios::fmtflags saved = out.flags();
    out << right << fixed;
    if ( !std::isfinite(v) )
    {
        out << setw(width) << v;
        out.flags(saved);
        return;
    }
    double roundedInt = std::round(v);
    if ( std::fabs(v - roundedInt) <= 1e-9 * (1.0 + std::fabs(v)) )
    {
        out << setw(width) << setprecision(0) << roundedInt;
        out.flags(saved);
        return;
    }
    double scale = std::pow(10.0, maxFracDigits);
    double r = std::round(v * scale) / scale;
    out << setw(width) << setprecision(maxFracDigits) << r;
    out.flags(saved);
}

void writeInpIntOrTwoFrac(ostream& out, int width, double v)
{
    writeInpIntOrFrac(out, width, v, 2);
}

/// True if a demand row matches the junction primary (already written under [JUNCTIONS]).
bool demandEqualsPrimaryRow(const Demand& d, const Demand& primary)
{
    if ( d.timePattern != primary.timePattern ) return false;
    double a = d.baseDemand;
    double b = primary.baseDemand;
    double scale = 1.0 + ( std::fabs(a) > std::fabs(b) ? std::fabs(a) : std::fabs(b) );
    return std::fabs(a - b) <= 1e-9 * scale;
}

} // namespace

//-----------------------------------------------------------------------------

ProjectWriter::ProjectWriter(): network(0)
{}

ProjectWriter::~ProjectWriter()
{}

//-----------------------------------------------------------------------------

//  Write the network's data base to a file using the EPANET INP format

int ProjectWriter::writeFile(const char* fname, Network* nw)
{
    if (nw == 0) return 0;
    network = nw;

    fout.open(fname, ios::out);
    if (!fout.is_open()) return FileError::CANNOT_OPEN_INPUT_FILE;

    writeTitle();
    writeJunctions();
    writeReservoirs();
    writeTanks();
    writePipes();
    writePumps();
    writeValves();
    writeTags();
    writeDemands();
    writeStatus();
    writePatterns();
    writeCurves();
    writeControls();
    writeRules();
    writeEnergy();
    writeEmitters();
    writeLeakages();
    writeQuality();
    writeSources();
    writeReactions();
    writeMixing();
    writeTimes();
    writeReport();
    writeOptions();
    writeCoords();
    writeAuxData();
    fout << "\n[END]\n";
    fout.close();
    return 0;
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeTitle()
{
    fout << "[TITLE]\n";
    network->writeTitle(fout);
    if ( !network->noriaExportVersion.empty() )
    {
        fout << "\n";
        fout << "exported by noria (" << network->noriaExportVersion << ")\n";
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeJunctions()
{
    fout << "\n[JUNCTIONS]\n";
    fout << ";ID              	Elev        	Demand      	Pattern         \n";
    for (Node* node : network->nodes)
    {
        if ( node->type() == Node::JUNCTION )
        {
            Junction* junc = static_cast<Junction*>(node);
            // Match EPANET 2.x: 16-char ID, tab, 12-char Elev, tab, 12-char Demand, tab, 16-char Pattern.
            fout << left << setw(16) << node->name << '\t';
            double elevDisplay = node->elev * network->ucf(Units::LENGTH);
            writeInpIntOrTwoFrac(fout, 12, elevDisplay);

            if ( network->option(Options::DEMAND_MODEL) == "FIXED" )
            {
                fout << '\t';
                double qDisplay = junc->primaryDemand.baseDemand * network->ucf(Units::FLOW);
                writeInpIntOrTwoFrac(fout, 12, qDisplay);
                string patStr;
                if ( junc->primaryDemand.timePattern )
                    patStr = junc->primaryDemand.timePattern->name;
                fout << '\t' << left << setw(16) << patStr;
            }
            else
            {
                // PDA: Demand / Pattern columns as '*', then min / full pressure (12-wide).
                fout << '\t' << left << setw(12) << "*";
                fout << '\t' << left << setw(12) << "*";
                double pUcf = network->ucf(Units::PRESSURE);
                fout << '\t';
                writeInpIntOrFrac(fout, 12, junc->pMin * pUcf, 2);
                fout << '\t';
                writeInpIntOrFrac(fout, 12, junc->pFull * pUcf, 2);
            }
            // Trailing tab + ';' matches EPANET 2.x (e.g. net1: ... \t;\r\n).
            fout << '\t' << ";\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeReservoirs()
{
    fout << "\n[RESERVOIRS]\n";
    fout << ";ID              	Head        	Pattern         \n";
    for (Node* node : network->nodes)
    {
        if ( node->type() == Node::RESERVOIR )
        {
            Reservoir* resv = static_cast<Reservoir*>(node);
            fout << left << setw(16) << node->name << '\t';
            double headDisplay = node->elev * network->ucf(Units::LENGTH);
            writeInpIntOrTwoFrac(fout, 12, headDisplay);
            string patStr;
            if ( resv->headPattern )
                patStr = resv->headPattern->name;
            fout << '\t' << left << setw(16) << patStr;
            fout << '\t' << ";\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeTanks()
{
    fout << "\n[TANKS]\n";
    fout << ";ID              	Elevation   	InitLevel   	MinLevel    	MaxLevel    	Diameter    	MinVol      	VolCurve        	Overflow\n";
    for (Node* node : network->nodes)
    {
        if ( node->type() == Node::TANK )
        {
            Tank* tank = static_cast<Tank*>(node);
            double ucfLength = network->ucf(Units::LENGTH);
            fout << left << setw(16) << node->name << '\t';
            writeInpIntOrTwoFrac(fout, 12, node->elev * ucfLength);
            writeInpIntOrTwoFrac(fout, 12, (tank->initHead - node->elev) * ucfLength);
            writeInpIntOrTwoFrac(fout, 12, (tank->minHead - node->elev) * ucfLength);
            writeInpIntOrTwoFrac(fout, 12, (tank->maxHead - node->elev) * ucfLength);
            writeInpIntOrTwoFrac(fout, 12, tank->diameter * ucfLength);
            writeInpIntOrTwoFrac(fout, 12, tank->minVolume * network->ucf(Units::VOLUME));
            fout << '\t' << left << setw(16);
            if ( tank->volCurve ) fout << tank->volCurve->name;
            fout << '\t' << left << setw(16) << "";
            fout << '\t' << ";\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writePipes()
{
    fout << "\n[PIPES]\n";
    fout << ";ID              	Node1           	Node2           	Length      	Diameter    	Roughness   	MinorLoss   	Status\n";
    for (Link* link : network->links)
    {
        if ( link->type() == Link::PIPE )
        {
            Pipe* pipe = static_cast<Pipe*>(link);
            fout << left << setw(16) << link->name << '\t';
            fout << left << setw(16) << link->fromNode->name << '\t';
            fout << left << setw(16) << link->toNode->name << '\t';
            writeInpIntOrTwoFrac(fout, 12, pipe->length * network->ucf(Units::LENGTH));
            writeInpIntOrTwoFrac(fout, 12, pipe->diameter * network->ucf(Units::DIAMETER));
            double r = pipe->roughness;
            if ( network->option(Options::HEADLOSS_MODEL ) == "D-W")
            {
                r = r * network->ucf(Units::LENGTH) * 1000.0;
            }
            writeInpIntOrTwoFrac(fout, 12, r);
            writeInpIntOrTwoFrac(fout, 12, pipe->lossCoeff);
            fout << '\t';
            if (pipe->hasCheckValve) fout << "CV";
            else if ( link->initStatus == Link::LINK_CLOSED ) fout << "CLOSED";
            else fout << "Open";
            fout << '\t' << ";\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writePumps()
{
    fout << "\n[PUMPS]\n";
    fout << ";ID              	Node1           	Node2           	Parameters\n";
    for (Link* link : network->links)
    {
        if ( link->type() == Link::PUMP )
        {
            Pump* pump = static_cast<Pump*>(link);
            fout << left << setw(16) << link->name << '\t';
            fout << left << setw(16) << link->fromNode->name << '\t';
            fout << left << setw(16) << link->toNode->name << '\t';

            if ( pump->pumpCurve.horsepower > 0.0 && pump->pumpCurve.curve == nullptr )
            {
                fout << setw(8) << "POWER";
                writeInpIntOrTwoFrac(fout, 12, pump->pumpCurve.horsepower * network->ucf(Units::POWER));
            }

            if ( pump->pumpCurve.curve != nullptr )
            {
                fout << setw(8) << "HEAD";
                fout << setw(16) << pump->pumpCurve.curve->name;
            }

            if ( pump->speed > 0.0 && pump->speed != 1.0 )
            {
                fout << setw(8) << "SPEED";
                writeInpIntOrTwoFrac(fout, 8, pump->speed);
            }

            if ( pump->speedPattern )
            {
                fout << setw(8) << "PATTERN";
                fout << setw(16) << pump->speedPattern->name;
            }
            fout << '\t' << ";\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeValves()
{
    fout << "\n[VALVES]\n";
    fout << ";ID              	Node1           	Node2           	Diameter    	Type	Setting     	MinorLoss   \n";
    for (Link* link : network->links)
    {
        if ( link->type() == Link::VALVE )
        {
            Valve* valve = static_cast<Valve*>(link);
            fout << left << setw(16) << link->name << '\t';
            fout << left << setw(16) << link->fromNode->name << '\t';
            fout << left << setw(16) << link->toNode->name << '\t';
            writeInpIntOrTwoFrac(fout, 12, valve->diameter*network->ucf(Units::DIAMETER));
            fout << '\t' << setw(8) << Valve::ValveTypeWords[(int)valve->valveType];

            if (valve->valveType == Valve::GPV)
            {
                fout << setw(16) << network->curve((int)link->initSetting)->name << '\t' << ";\n";
            }
            else
            {
                double cf = link->initSetting /
                            link->convertSetting(network, link->initSetting);
                writeInpIntOrTwoFrac(fout, 12, cf * link->initSetting);
                fout << '\t' << ";\n";
            }
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeDemands()
{
    fout << "\n[DEMANDS]\n";
    fout << ";Junction        	Demand      	Pattern         	Category\n";
    for (Node* node : network->nodes)
    {
        if ( node->type() == Node::JUNCTION )
    	{
    	    Junction* junc = static_cast<Junction*>(node);
    	    fout << left;
    	    auto demand = junc->demands.begin();
    	    while ( demand != junc->demands.end() )
    	    {
    	        // Primary demand is written on [JUNCTIONS]; skip duplicate row (see Junction::convertUnits).
    	        if ( demandEqualsPrimaryRow(*demand, junc->primaryDemand) )
    	        {
    	            ++demand;
    	            continue;
    	        }
    	        fout << setw(16) << node->name << '\t';
    	        writeInpIntOrTwoFrac(fout, 12, demand->baseDemand * network->ucf(Units::FLOW));
    	        fout << '\t' << left << setw(16);
    	        if (demand->timePattern != 0)
    	            fout << demand->timePattern->name;
    	        fout << '\t' << left << setw(16) << "";
    	        fout << '\t' << ";\n";
    	        ++demand;
    	    }
    	}
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeEmitters()
{
    fout << "\n[EMITTERS]\n";
    fout << ";Junction        	Coefficient\n";
    for (Node* node : network->nodes)
    {
        if ( node->type() == Node::JUNCTION )
        {
            Junction* junc = static_cast<Junction*>(node);
            Emitter* emitter = junc->emitter;
            if ( emitter )
            {
                fout << left << setw(16) << node->name << '\t';
                double qUcf = network->ucf(Units::FLOW);
                double pUcf = network->ucf(Units::PRESSURE);
                writeInpIntOrTwoFrac(fout, 12, emitter->flowCoeff * qUcf * pow(pUcf, emitter->expon));
                writeInpIntOrTwoFrac(fout, 12, emitter->expon);
                if ( emitter->timePattern != 0 ) fout << '\t' << setw(16) << emitter->timePattern->name;
                fout << '\t' << ";\n";
            }
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeLeakages()
{
    // EPANET 2.x has no [LEAKAGES]; omit the section when empty so Save As .inp runs in EPANET 2.2.
    bool any = false;
    for (Link* link : network->links)
    {
        if ( link->type() == Link::PIPE )
        {
            Pipe* pipe = static_cast<Pipe*>(link);
            if ( pipe->leakCoeff1 > 0.0 ) { any = true; break; }
        }
    }
    if ( !any ) return;

    fout << "\n[LEAKAGES]\n";
    for (Link* link : network->links)
    {
        if ( link->type() == Link::PIPE )
        {
            Pipe* pipe = static_cast<Pipe*>(link);
            if ( pipe->leakCoeff1 > 0.0 )
            {
                fout << left << setw(16) << link->name << '\t';
                writeInpIntOrTwoFrac(fout, 12, pipe->leakCoeff1);
                writeInpIntOrTwoFrac(fout, 12, pipe->leakCoeff2);
                fout << '\t' << ";\n";
            }
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeStatus()
{
    fout << "\n[STATUS]\n";
    fout << ";ID              	Status/Setting\n";
    for (Link* link : network->links)
    {
    	if ( link->type() == Link::PUMP )
    	{
    	    if ( link->initSetting == 0 || link->initStatus == Link::LINK_CLOSED )
    	    {
    	        fout << left << setw(16) << link->name << "  CLOSED\t;\n";
    	    }
    	}
    	else if ( link->type() == Link::VALVE )
    	{
    	    if ( link->initStatus == Link::LINK_OPEN || link->initStatus == Link::LINK_CLOSED )
    	    {
    	        fout << left << setw(16) << link->name << " ";
    	        if (link->initStatus == Link::LINK_OPEN) fout << "OPEN\t;\n";
    	        else fout << "CLOSED\t;\n";
    	    }
    	}
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writePatterns()
{
    fout << "\n[PATTERNS]\n";
    fout << ";ID              	Multipliers\n";
    for (Pattern* pattern : network->patterns)
    {
    	if ( pattern->type == Pattern::FIXED_PATTERN )
    	{
            // EPANET 2.x [PATTERNS] uses multiplier rows only (no FIXED / VARIABLE keywords).
            int k = 0;
            int i = 0;
            int n = pattern->size();
            while ( i < n )
            {
                if ( k == 0 ) fout << left << setw(16) << pattern->name << "  ";
                writeInpIntOrTwoFrac(fout, 12, pattern->factor(i));
                i++;
                k++;
                if ( k == 5 ) { fout << "\n"; k = 0; }
            }
            if ( k != 0 ) fout << "\n";
        }
    	else if (pattern-> type == Pattern::VARIABLE_PATTERN )
    	{
    	    VariablePattern* vp = static_cast<VariablePattern*>(pattern);
    	    fout << left << setw(16) << pattern->name << " VARIABLE ";
    	    for (int i = 0; i < pattern->size(); i++)
    	    {
    	        fout << "\n" << setw(16) << pattern->name << "  ";
    	        fout << Utilities::getTime((int)vp->time(i)) << '\t';
    	        writeInpIntOrTwoFrac(fout, 12, vp->factor(i));
    	        fout << "\n";
    	    }
    	}
        fout << "\n";
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeCurves()
{
    fout << "\n[CURVES]\n";
    fout << ";ID              	X-Value     	Y-Value\n";
    for (Curve* curve : network->curves)
    {
        for (int i = 0; i < curve->size(); i++)
        {
            fout << left << setw(16) << curve->name << "  ";
            writeInpIntOrTwoFrac(fout, 12, curve->x(i));
            writeInpIntOrTwoFrac(fout, 12, curve->y(i));
            fout << "\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeControls()
{
    fout << "\n[CONTROLS]\n";
    for (Control* control : network->controls)
    {
        fout << control->toStr(network) << "\n";
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeEnergy()
{
    fout << "\n[ENERGY]\n";
    fout << network->options.energyOptionsToStr(network);
    for (Link* link : network->links)
    {
    	if ( link->type() == Link::PUMP )
    	{
    	    Pump* pump = static_cast<Pump*>(link);
    	    fout << left;
    	    if ( pump->efficCurve )
    	    {
    	        fout << "PUMP  " << link->name << "  " << "EFFIC  ";
    	        fout << pump->efficCurve->name << "\n";
    	    }

    	    if ( pump->costPerKwh > 0.0 )
    	    {
    	        fout << "PUMP  " << link->name << "  " << "PRICE  " << Utilities::inpDoubleToStr(pump->costPerKwh) << "\n";
    	    }

    	    if ( pump->costPattern )
    	    {
    	        fout << "PUMP  " << link->name << "  " << "PATTERN  ";
    	        fout << pump->costPattern->name << "\n";
    	    }
    	}
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeQuality()
{
    fout << "\n[QUALITY]\n";
    fout << ";Node            	InitQual\n";
    for (Node* node : network->nodes)
    {
        if (node->initQual > 0.0)
        {
            fout << left << setw(16) << node->name << '\t';
            writeInpIntOrTwoFrac(fout, 12, node->initQual * network->ucf(Units::CONCEN));
            fout << "\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeSources()
{
    fout << "\n[SOURCES]\n";
    fout << ";Node            	Type        	Quality     	Pattern\n";
    for (Node* node : network->nodes)
    {
        if ( node->qualSource && node->qualSource->base > 0.0)
        {
            fout << left << setw(16) << node->name << '\t';
            fout << left << setw(12) << QualSource::SourceTypeWords[node->qualSource->type] << '\t';
            writeInpIntOrTwoFrac(fout, 12, node->qualSource->base);
            fout << '\t';
            if ( node->qualSource->pattern )
                fout << node->qualSource->pattern->name;
            fout << "\n";
        }
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeMixing()
{
    fout << "\n[MIXING]\n";
    fout << ";Tank            	Model\n";
    for (Node* node : network->nodes)
    {
        if ( node->type() == Node::TANK )
    	{
    	    Tank* tank = static_cast<Tank*>(node);
    	    fout << left << setw(16) << node->name << '\t';
    	    fout << left << setw(12) << TankMixModel::MixingModelWords[tank->mixingModel.type] << '\t';
    	    writeInpIntOrTwoFrac(fout, 12, tank->mixingModel.fracMixed);
    	    fout << "\n";
    	}
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeReactions()
{
    fout << "\n[REACTIONS]\n";
    fout << network->options.reactOptionsToStr();
    double defBulkCoeff = network->option(Options::BULK_COEFF);
    double defWallCoeff = network->option(Options::WALL_COEFF);

    for (Link* link : network->links)
    {
     	if ( link->type() == Link::PIPE )
    	{
    	    Pipe* pipe = static_cast<Pipe*>(link);
            fout << left;
            if ( pipe->bulkCoeff != defBulkCoeff )
            {
                fout << "BULK      ";
                fout << setw(16) << link->name << " ";
                fout << Utilities::inpDoubleToStr(pipe->bulkCoeff) << "\n";
            }
            if ( pipe->wallCoeff != defWallCoeff )
            {
                fout << "WALL      ";
                fout << setw(16) << link->name << " ";
                fout << Utilities::inpDoubleToStr(pipe->wallCoeff) << "\n";
            }
    	}
    }

    for (Node* node : network->nodes)
    {
        if ( node->type() == Node::TANK )
    	{
    	    Tank* tank = static_cast<Tank*>(node);
    	    if ( tank->bulkCoeff != defBulkCoeff )
    	    {
    	        fout << "TANK      ";
    	        fout << setw(16) << node->name << " ";
    	        fout << Utilities::inpDoubleToStr(tank->bulkCoeff) << "\n";
    	    }
    	}
    }
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeOptions()
{
    fout << "\n[OPTIONS]\n";
    fout << network->options.epanet2OptionsToStr(network);
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeTimes()
{
    fout << "\n[TIMES]\n";
    fout << network->options.epanet2TimeOptionsToStr();
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeReport()
{
    fout << "\n[REPORT]\n";
    fout << network->options.reportOptionsToStr();
}

void ProjectWriter::writeTags()
{
    fout << "\n[TAGS]\n";
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeRules()
{
    fout << "\n[RULES]\n";
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeVertices()
{
    fout << "\n[VERTICES]\n";
    fout << ";Link            	X-Coord           	Y-Coord\n";
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeLabels()
{
    fout << "\n[LABELS]\n";
    fout << ";X-Coord             Y-Coord             Label & Anchor Node\n";
}

//-----------------------------------------------------------------------------

void ProjectWriter::writeBackdrop()
{
    fout << "\n[BACKDROP]\n";
}

void ProjectWriter::writeCoords()
{
    bool wroteHeader = false;
    for (Node* node : network->nodes)
    {
        if ( node->xCoord > -1e19 && node->yCoord > -1e19 )
        {
            if ( !wroteHeader )
            {
                fout << "\n[COORDINATES]\n";
                fout << ";Node            	X-Coord           	Y-Coord\n";
                wroteHeader = true;
            }
            fout << left << setw(16) << node->name << '\t';
            writeInpIntOrFrac(fout, 18, node->xCoord, 3);
            writeInpIntOrFrac(fout, 18, node->yCoord, 3);
            fout << "\n";
        }
    }
}

void ProjectWriter::writeAuxData()
{
    writeVertices();
    writeLabels();
    writeBackdrop();
}
