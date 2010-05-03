// jat.h - Just Another Translator - 

#include <stdio.h>  

// antlr generated
#include    "jalLexer.h"
#include    "jalParser.h"

#include    "symboltable.h"

// command line switches
extern int Verbose;
extern int NoInclude;

// more indent levels with verbose:
#define VLEVEL (Verbose > 0 ? 1 : 0) 

// main function prototypes
void TreeWalkWorker(pANTLR3_BASE_TREE p, int Level);
pANTLR3_INPUT_STREAM JalOpenInclude(char *Line);


// parser.c
jalParser_program_return ParseSource(pANTLR3_UINT8 fName);


// codegen.c
char *VarTypeString(int TokenType);
char *GetUniqueIdentifier(void);
char *DeRefSub(char *InString, char CallMethod);
void PrintJ2cString(char *String);
void Indent(int Level);

char *DeReference    (Context *co, char *InString);
char GetCallMethod   (Context *co, char *ParamName);


void CodeGenerate(pANTLR3_BASE_TREE t);

int CgExpression     (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgAssign        (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgCaseValue     (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgCase          (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgFor           (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgWhile         (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgRepeat        (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgSingleVar     (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgVar           (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgParamChilds   (Context *co, pANTLR3_BASE_TREE t, int Level, SymbolParam *p, int VarType);
void CgParams        (Context *co, pANTLR3_BASE_TREE t, int Level, SymbolFunction *f);
void CgProcedureDef  (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgConst         (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgIf            (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgForever       (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgStatements    (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgProcFuncCall  (Context *co, pANTLR3_BASE_TREE t, int Level);
void CgStatement     (Context *co, pANTLR3_BASE_TREE t, int Level);











