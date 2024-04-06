use verilock::analysis;
use verilock::task;
use verilock::task::Case;

use std::env;
use std::path::PathBuf;

fn main() {
    let vec: Vec<String> = env::args().collect();
    let args = &vec[1..];
    if args.is_empty() {
        perform_both_experiments();
    } else {
        let flag = &args[0].to_uppercase();
        if flag == "-F" {
            if args.len() == 2 {
                let experiment = &args[1].to_uppercase();
                if experiment == "RQ1" {
                    rq1_flatten();
                } else if experiment == "RQ2" {
                    rq2_flatten();
                } else {
                    println!("Unrecognizable experiment: {}", experiment);
                }
            } else if args.len() == 3 {
                let action = &args[1].to_uppercase();
                if action == "CHECK" {
                    check_flatten(&args[2]);
                } else if action == "SINGLE" {
                    single_flatten(&args[2]);
                } else {
                    println!("Unrecognizable action: {}", action);
                }
            } else {
                println!("wrong arguments: {}", args.join(" "));
            }
        } else if args.len() == 1 {
            let arg = args.first().unwrap().to_uppercase();
            if arg == "RQ1" {
                rq1();
            } else if arg == "RQ2" {
                rq2();
            } else {
                println!("Unrecognizable command-line arg: {arg}");
            }
        } else if args.len() == 2 {
            let first = &args[0].to_uppercase();
            if first == "CHECK" {
                check(&args[1]);
            } else if first == "SINGLE" {
                single(&args[1]);
            } else {
                println!("Unrecognizable command-line args: {}", args.join(" "));
            }
        } else {
            println!("too many arguments: {}", args.join(" "));
        }
    }
}

fn perform_both_experiments() {
    println!("Perform both experiments");
    rq1();
    rq2();
}

fn rq1_flatten() {
    task::EXPERIMENT1.iter().for_each(analyze_flatten_with_info);
}

fn rq2_flatten() {
    task::EXPERIMENT2.iter().for_each(analyze_flatten_with_info);
}

fn rq1() {
    task::EXPERIMENT1.iter().for_each(analyze_with_info);
}

fn rq2() {
    task::EXPERIMENT2.iter().for_each(analyze_with_info);
}

fn single_flatten(c: &str) {
    let case_name = c.to_uppercase();
    let case_name = case_name.as_str();
    match case_name {
        "CASE1" => analyze_flatten_with_info(&task::VC1),
        "CASE2" => analyze_flatten_with_info(&task::VC2),
        "CASE3" => analyze_flatten_with_info(&task::VC3),
        "CASE4" => analyze_flatten_with_info(&task::VC4),
        "CASE5" => analyze_flatten_with_info(&task::VC5),
        "CASE6" => analyze_flatten_with_info(&task::VC6),
        "CASE7" => analyze_flatten_with_info(&task::VC7),
        "CASE8" => analyze_flatten_with_info(&task::VC8),
        "CASE1D" => analyze_flatten_with_info(&task::VC1_),
        "CASE2D" => analyze_flatten_with_info(&task::VC2_),
        "CASE3D" => analyze_flatten_with_info(&task::VC3_),
        "CASE4D" => analyze_flatten_with_info(&task::VC4_),
        "CASE5D" => analyze_flatten_with_info(&task::VC5_),
        "CASE6D" => analyze_flatten_with_info(&task::VC6_),
        "CASE7D" => analyze_flatten_with_info(&task::VC7_),
        "CASE8D" => analyze_flatten_with_info(&task::VC8_),
        name if name.starts_with("GEN") => {
            let num = name.chars().skip(3).collect::<String>();
            let num = num.parse::<usize>().unwrap();
            analyze_flatten_with_info(&task::gen(num))
        },
        _ => panic!("invalid case name"),
    }
}

fn single(c: &str) {
    let case_name = c.to_uppercase();
    let case_name = case_name.as_str();
    match case_name {
        "CASE1" => analyze_with_info(&task::VC1),
        "CASE2" => analyze_with_info(&task::VC2),
        "CASE3" => analyze_with_info(&task::VC3),
        "CASE4" => analyze_with_info(&task::VC4),
        "CASE5" => analyze_with_info(&task::VC5),
        "CASE6" => analyze_with_info(&task::VC6),
        "CASE7" => analyze_with_info(&task::VC7),
        "CASE8" => analyze_with_info(&task::VC8),
        "CASE1D" => analyze_with_info(&task::VC1_),
        "CASE2D" => analyze_with_info(&task::VC2_),
        "CASE3D" => analyze_with_info(&task::VC3_),
        "CASE4D" => analyze_with_info(&task::VC4_),
        "CASE5D" => analyze_with_info(&task::VC5_),
        "CASE6D" => analyze_with_info(&task::VC6_),
        "CASE7D" => analyze_with_info(&task::VC7_),
        "CASE8D" => analyze_with_info(&task::VC8_),
        name if name.starts_with("GEN") => {
            let num = name.chars().skip(3).collect::<String>();
            let num = num.parse::<usize>().unwrap();
            analyze_with_info(&task::gen(num))
        },
        _ => panic!("invalid case name"),
    }
}

fn analyze_flatten_with_info(c: &Case) {
    c.get_name().map(print_boxed_name);
    println!("-------------------");
    analysis::analyze(c, true);
    println!("-------------------");
}

fn analyze_with_info(c: &Case) {
    c.get_name().map(print_boxed_name);
    println!("-------------------");
    analysis::analyze(c, false);
    println!("-------------------");
}

fn print_boxed_name(name: &str) {
    let len = name.len();
    let line = [String::from("+"), "-".repeat(len), String::from("+")].join("");
    println!("{}", line);
    println!("|{}|", name);
    println!("{}", line);
}

fn check_flatten(p: &String) {
    let case = Case {
        path: Box::new(PathBuf::from(p)),
        identifier: task::ID.clone(),
    };
    analysis::analyze(&case, true)
}

fn check(p: &String) {
    let case = Case {
        path: Box::new(PathBuf::from(p)),
        identifier: task::ID.clone(),
    };
    analysis::analyze(&case, false)
}
