package main

import (
	"android/bazel/mkcompare"
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"math"
	"os"
	"runtime"
	"runtime/pprof"
	"sort"
	"strings"
)

var cpuprofile = flag.String("cpuprofile", "", "write cpu profile to `file`")
var memprofile = flag.String("memprofile", "", "write memory profile to `file`")
var ignoredVariables = flag.String("ignore_variables", "", "comma-separated list of variables to ignore")
var maxDiff = flag.Int("max", math.MaxInt, "stop after finding N different modules")
var showPerModuleDiffs = flag.Bool("show_module_diffs", false, "show per-module differences")
var showModulesPerType = flag.Bool("show_type_modules", false, "show modules for each differing type")
var jsonOut = flag.Bool("json", false, "generate JSON output")
var showSummary = flag.Bool("show_summary", true, "show summary")
var ignoredVarSet map[string]bool

func maybeQuit(err error) {
	if err == nil {
		return
	}

	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

func parse(path string) *mkcompare.MkFile {
	f, err := os.Open(path)
	maybeQuit(err)
	mkFile, err := mkcompare.ParseMkFile(bufio.NewReader(f))
	maybeQuit(err)
	f.Close()
	return mkFile
}

func processArgs() {
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, `usage: mkcompare <options> refMkFile mkFile`)
		flag.PrintDefaults()
		os.Exit(2)
	}
	flag.Parse()
	if len(flag.Args()) != 2 {
		flag.Usage()
	}
	if *jsonOut {
		*showPerModuleDiffs = false
		*showModulesPerType = false
		*showSummary = false
	}
}

func goParse(path string) chan *mkcompare.MkFile {
	ch := make(chan *mkcompare.MkFile, 1)
	go func() { ch <- parse(path) }()
	return ch
}

func printVars(title string, modulesByVar map[string][]string, mkFile *mkcompare.MkFile) {
	if len(modulesByVar) > 0 {
		fmt.Println(title)
		for varName, mods := range modulesByVar {
			printModulesByType(fmt.Sprintf("  %s, by type:", varName), mods, mkFile)
		}
	}
}

func printModulesByType(title string, moduleNames []string, mkFile *mkcompare.MkFile) {
	// Indent all lines by the title's indent
	prefix := title
	for i, c := range title {
		if string(c) != " " {
			prefix = title[0:i]
			break
		}
	}
	fmt.Println(title)
	sortedTypes, byType := mkFile.ModulesByType(moduleNames)
	for _, typ := range sortedTypes {
		fmt.Printf("%s  %s (%d modules)\n", prefix, typ, len(byType[typ]))
		if !*showPerModuleDiffs {
			continue
		}
		for _, m := range byType[typ] {
			fmt.Println(prefix, "  ", m)
		}
	}
}

type diffMod struct {
	mkcompare.MkModuleDiff
	Name        string
	RefLocation int
	OurLocation int
}

type Diff struct {
	RefPath        string
	OurPath        string
	ExtraModules   []string
	MissingModules []string
	DiffModules    []diffMod
}

func process(refMkFile, ourMkFile *mkcompare.MkFile) bool {
	diff := Diff{RefPath: refMkFile.Path, OurPath: ourMkFile.Path}
	var commonModules []string
	diff.MissingModules, commonModules, diff.ExtraModules =
		mkcompare.Classify(refMkFile.Modules, ourMkFile.Modules, func(_ string) bool { return true })

	sort.Strings(diff.MissingModules)
	if *showSummary && len(diff.MissingModules) > 0 {
		printModulesByType(fmt.Sprintf("%d missing modules, by type:", len(diff.MissingModules)),
			diff.MissingModules, refMkFile)
	}

	sort.Strings(diff.ExtraModules)
	if *showSummary && len(diff.ExtraModules) > 0 {
		printModulesByType(fmt.Sprintf("%d extra modules, by type:", len(diff.ExtraModules)), diff.ExtraModules, ourMkFile)
	}
	filesAreEqual := len(diff.MissingModules)+len(diff.ExtraModules) == 0

	nDiff := 0
	sort.Strings(commonModules)
	filterVars := func(name string) bool {
		_, ok := ignoredVarSet[name]
		return !ok
	}
	var missingVariables = make(map[string][]string)
	var extraVariables = make(map[string][]string)
	var diffVariables = make(map[string][]string)
	for _, m := range commonModules {
		d := mkcompare.Compare(refMkFile.Modules[m], ourMkFile.Modules[m], filterVars)
		if d.Empty() {
			continue
		}
		filesAreEqual = false
		diff.DiffModules = append(diff.DiffModules, diffMod{
			MkModuleDiff: d,
			Name:         m,
			RefLocation:  d.Ref.Location,
			OurLocation:  d.Our.Location,
		})
		nDiff = nDiff + 1
		if nDiff >= *maxDiff {
			fmt.Printf("Only the first %d module diffs are processed\n", *maxDiff)
			break
		}
		addToDiffList := func(d map[string][]string, items []string) {
			if len(items) == 0 {
				return
			}
			for _, v := range items {
				d[v] = append(d[v], m)
			}
		}
		addToDiffList(missingVariables, d.MissingVars)
		addToDiffList(extraVariables, d.ExtraVars)
		for _, dv := range d.DiffVars {
			diffVariables[dv.Name] = append(diffVariables[dv.Name], m)
		}
		if *showPerModuleDiffs {
			fmt.Println()
			d.Print(os.Stdout, m)
		}
	}
	if *showSummary {
		printVars(fmt.Sprintf("\nMissing variables (%d):", len(missingVariables)), missingVariables, refMkFile)
		printVars(fmt.Sprintf("\nExtra variables (%d):", len(extraVariables)), extraVariables, ourMkFile)
		printVars(fmt.Sprintf("\nDiff variables: (%d)", len(diffVariables)), diffVariables, refMkFile)
	}
	if *jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		enc.Encode(diff)
	}
	return filesAreEqual
}

func main() {
	processArgs()
	if *cpuprofile != "" {
		f, err := os.Create(*cpuprofile)
		maybeQuit(err)
		defer f.Close() // error handling omitted for example
		maybeQuit(pprof.StartCPUProfile(f))
		defer pprof.StopCPUProfile()
	}
	chRef := goParse(flag.Arg(0))
	chNew := goParse(flag.Arg(1))
	if *ignoredVariables != "" {
		ignoredVarSet = make(map[string]bool)
		for _, v := range strings.Split(*ignoredVariables, ",") {
			ignoredVarSet[v] = true
		}
	}
	refMkFile, newMkFile := <-chRef, <-chNew
	refMkFile.Path = flag.Arg(0)
	newMkFile.Path = flag.Arg(1)
	equal := process(refMkFile, newMkFile)
	if *memprofile != "" {
		f, err := os.Create(*memprofile)
		maybeQuit(err)
		defer f.Close() // error handling omitted for example
		runtime.GC()    // get up-to-date statistics
		maybeQuit(pprof.WriteHeapProfile(f))
	}
	if !equal {
		os.Exit(2)
	}
}
