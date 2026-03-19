# lean4export NDJSON Format Reference (v3.1.0)

Each line is a self-contained JSON object. Names, levels, and expressions are assigned
integer IDs via `in`, `il`, `ie` keys. Declarations reference these IDs.

## Initial metadata
```json
{"meta": {"exporter": {"name": str, "version": str}, "lean": {"githash": str, "version": str}, "format": {"version": str}}}
```

## Names
```json
{"in": 0}                                          // Name.anonymous (id 0 is always anonymous)
{"str": {"pre": 0, "str": "Lean"}, "in": 1}        // Name.str: parent=0, string="Lean"
{"num": {"pre": 0, "i": 42}, "in": 2}              // Name.num: parent=0, number=42
```

## Levels
```json
{"il": 0}                                          // Level.zero (id 0 is always zero)
{"succ": 0, "il": 1}                               // Level.succ: pred=level#0
{"max": [1, 2], "il": 3}                           // Level.max: lhs=level#1, rhs=level#2
{"imax": [1, 2], "il": 4}                          // Level.imax: lhs=level#1, rhs=level#2
{"param": 5, "il": 5}                              // Level.param: name=name#5
```

## Expressions
```json
{"bvar": 0, "ie": 0}                               // Expr.bvar: de Bruijn index 0
{"sort": 0, "ie": 1}                               // Expr.sort: level=level#0
{"const": {"name": 1, "us": [0, 1]}, "ie": 2}      // Expr.const: name=name#1, levels=[level#0, level#1]
{"app": {"fn": 3, "arg": 4}, "ie": 5}              // Expr.app: fn=expr#3, arg=expr#4
{"lam": {"name": 1, "type": 2, "body": 3, "bi": "default"}, "ie": 6}     // Expr.lambda
{"forallE": {"name": 1, "type": 2, "body": 3, "bi": "default"}, "ie": 7} // Expr.forall
{"letE": {"name": 1, "type": 2, "value": 3, "body": 4, "nondep": false}, "ie": 8}  // Expr.let
{"proj": {"typeName": 1, "idx": 0, "struct": 5}, "ie": 9}               // Expr.proj
{"natVal": "123", "ie": 10}                         // Expr.lit (nat) — note: value is a STRING
{"strVal": "hello", "ie": 11}                       // Expr.lit (str)
{"mdata": {"expr": 5, "data": {}}, "ie": 12}        // Expr.mdata: wraps expr#5
```

binderInfo values: "default", "implicit", "strictImplicit", "instImplicit"

## Declarations
```json
{"axiom": {"name": 1, "levelParams": [0], "type": 5, "isUnsafe": false}}
{"def": {"name": 2, "levelParams": [], "type": 10, "value": 20, "hints": "abbrev", "safety": "safe", "all": [2]}}
{"def": {"name": 3, "levelParams": [], "type": 10, "value": 20, "hints": {"regular": 5}, "safety": "safe", "all": [3]}}
{"thm": {"name": 4, "levelParams": [], "type": 10, "value": 20, "all": [4]}}
{"opaque": {"name": 5, "levelParams": [], "type": 10, "value": 20, "isUnsafe": false, "all": [5]}}
{"quot": {"name": 6, "levelParams": [0], "type": 10, "kind": "type"}}

{"inductive": {
  "types": [{"name": 1, "levelParams": [], "type": 5, "numParams": 0, "numIndices": 0,
             "all": [1], "ctors": [2], "numNested": 0, "isRec": false, "isUnsafe": false, "isReflexive": false}],
  "ctors": [{"name": 2, "levelParams": [], "type": 6, "induct": 1, "cidx": 0,
             "numParams": 0, "numFields": 0, "isUnsafe": false}],
  "recs":  [{"name": 3, "levelParams": [], "type": 7, "all": [1], "numParams": 0,
             "numIndices": 0, "numMotives": 1, "numMinors": 1,
             "rules": [{"ctor": 2, "nfields": 0, "rhs": 8}], "k": true, "isUnsafe": false}]
}}
```

hints: "opaque" | "abbrev" | {"regular": int}
safety: "safe" | "unsafe" | "partial"
quot kind: "type" | "ctor" | "lift" | "ind"
