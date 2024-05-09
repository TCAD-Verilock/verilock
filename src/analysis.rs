use std::collections::{HashMap, VecDeque};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::thread;
use std::time::{Instant, Duration};

use z3::{Config, Context, Solver};

use crate::abstraction::protocol::{Connect, DependencyForest, DependencyTree, extract_protocol, SessionComplex, TypedModule};
use crate::abstraction::sv_info::{Channel, ModuleInfo, ModuleInstance, Var};
use crate::cfsm::fsm::{Cfsm, construct_cfsm_from_module_instance, Fsm};
use crate::cfsm::synthesis::{Group, synthesize};
use crate::error::VerilockError;
use crate::parser;
use crate::task::Case;

type VerificationTask = ModuleInfo;

type TaskQueue = VecDeque<VerificationTask>;

pub fn timed_analyze(c: &Case, flatten: bool) {
    let start = Instant::now();
    let (timer_sender, timer_receiver): (Sender<Result<(), u64>>, _) = channel();
    let worker_sender = timer_sender.clone();
    let _ = thread::spawn(move || {
        let timeout = 600;
        thread::sleep(Duration::from_secs(timeout));
        let _ = timer_sender.send(Err(timeout));
    });
    let case = c.clone();
    let (abort_sender, abort_receiver) : (Sender<()>, _) = channel();
    let _ = thread::spawn(move || {
        parse_and_analyze(case, flatten, abort_receiver);
        let _ = worker_sender.send(Ok(()));
    });
    match timer_receiver.recv() {
        Err(_) => println!("Channel error"),
        Ok(r) => match r {
            Ok(_) => {
                let duration = start.elapsed();
                println!("Time elapsed in verification is: {:?}", duration);
            },
            Err(e) => {
                let _ = abort_sender.send(());
                eprintln!("Time out after {} seconds", e)
            },
        },
    }
}

fn parse_and_analyze(c: Case, flatten: bool, abort_receiver: Receiver<()>) {
    let path = &c.path;
    let id = &c.identifier;
    let project = parser::parse_project(path);
    let session_types = extract_protocol(&project, id);
    match session_types {
        Ok(t) => {
            let SessionComplex {
                dependency_forest,
                modules,
                module_instances,
                channel_instances: _,
                connections,
            } = t;
            let type_map = type_map(&modules);
            analyze_dependency_forest(
                dependency_forest,
                &type_map,
                &module_instances,
                &connections,
                flatten,
                abort_receiver)
        }
        Err(e) => e.report(),
    };
}

fn analyze_dependency_forest(
    forest: DependencyForest,
    type_map: &HashMap<String, TypedModule>,
    module_instances: &[ModuleInstance],
    connections: &[Connect],
    flatten: bool,
    abort_receiver: Receiver<()>
) {
    let config = Config::new();
    let context = Context::new(&config);
    let solver = Solver::new(&context);
    if flatten {
        analyze_forest_flatten(forest, type_map, module_instances, connections, &solver, abort_receiver)
    } else {
        analyze_forest_parallel(forest, type_map, module_instances, connections, &solver, abort_receiver)
    }
}

fn analyze_forest_flatten(
    forest: DependencyForest,
    type_map: &HashMap<String, TypedModule>,
    module_instances: &[ModuleInstance],
    connections: &[Connect],
    solver: &Solver,
    abort_receiver: Receiver<()>
) {
    let mut group = Group::new();
    for tree in forest {
        let mut map: HashMap<TypedModule, Group> = HashMap::new();
        let root_id = tree.root_node_id().unwrap();
        for id in tree.traverse_post_order_ids(root_id).unwrap() {
            let m = tree.get(&id).unwrap().data().clone();
            let mut sub_group = Group::new();
            let sub_modules = retrieve_instance_in_scope(&m, module_instances);
            let connect_in_scope = retrieve_connect_in_scope(&m, connections);
            for sub_module in sub_modules {
                let typed_module = &type_map[&sub_module.type_name];
                for (k, v) in lookup_group_or_instantiate(
                    typed_module,
                    &sub_module,
                    &connect_in_scope,
                    &mut map,
                ) {
                    sub_group.insert(k.prefix_scope(&m.module_name).prefix_instance(&sub_module.instance_name), v);
                }
            }
            let parent = ModuleInstance::group_parent(&m.module_name);
            let parent_cfsm = construct_cfsm_from_module_instance(
                &type_map[&parent.type_name].module,
                &parent,
                type_map[&parent.type_name].protocol.clone(),
                &connect_in_scope,
            );
            sub_group.insert(parent, parent_cfsm);
            map.insert(type_map[&m.module_name].clone(), sub_group);
        }
        let root = tree.get(root_id).unwrap().data().clone();
        for (k, v) in map.get(&type_map[&root.module_name]).unwrap() {
            group.insert(k.clone(), v.clone());
        }
    }
    let virtual_parent = ModuleInfo {
        module_name: String::from("VirtualParent"),
        ports: vec![],
    };
    match synthesize(group, virtual_parent, solver, &abort_receiver) {
        Ok(_) => println!("verified"),
        Err(e) => e.report(),
    }
}

fn analyze_forest_parallel(
    forest: DependencyForest,
    type_map: &HashMap<String, TypedModule>,
    module_instances: &[ModuleInstance],
    connections: &[Connect],
    solver: &Solver,
    abort_receiver: Receiver<()>
) {
    let mut error_detected = false;
    for tree in forest {
        match analyze_dependency_tree(
            tree,
            type_map,
            module_instances,
            connections,
            solver,
            &abort_receiver
        ) {
            Ok(_) => {}
            Err(e) => {
                error_detected = true;
                e.report();
                break;
            }
        }
    }
    if !error_detected {
        println!("verified")
    }
}

fn type_map(types: &Vec<TypedModule>) -> HashMap<String, TypedModule> {
    let mut map = HashMap::new();
    for t in types {
        map.insert(t.module.module_name.clone(), t.clone());
    }
    map
}

fn analyze_dependency_tree(
    tree: DependencyTree,
    type_map: &HashMap<String, TypedModule>,
    module_instances: &[ModuleInstance],
    connections: &[Connect],
    solver: &Solver,
    abort_receiver: &Receiver<()>
) -> Result<(), VerilockError> {
    let mut queue = dependency_tree_to_task_queue(&tree);
    let mut cfsm_map = HashMap::new();
    while let Some(task) = queue.pop_front() {
        let mut group = Group::new();
        // according to instantiation and dependency tree, construct communication group
        let sub_modules = retrieve_instance_in_scope(&task, module_instances);
        let connect_in_scope = retrieve_connect_in_scope(&task, connections);
        for sub_module in sub_modules {
            let cfsm = lookup_or_instantiate(
                &type_map[&sub_module.type_name],
                &sub_module,
                &connect_in_scope,
                &mut cfsm_map,
            );
            group.insert(sub_module, cfsm);
        }
        let parent = ModuleInstance::group_parent(&task.module_name);
        let parent_cfsm = lookup_or_instantiate(
            &type_map[&parent.type_name],
            &parent,
            &connect_in_scope,
            &mut cfsm_map,
        );
        group.insert(parent, parent_cfsm);
        match synthesize(group, cfsm_map[&task.module_name].clone().module, solver, abort_receiver) {
            Ok(cfsm) => {
                // update the CFSM map with the synthesized CFSM
                cfsm_map.insert(task.module_name.clone(), cfsm);
            }
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

fn lookup_or_instantiate(
    typed_module: &TypedModule,
    instance: &ModuleInstance,
    connections: &Vec<Connect>,
    cfsm_map: &mut HashMap<String, Cfsm>,
) -> Cfsm {
    if !cfsm_map.contains_key(&instance.type_name) {
        let cfsm = construct_cfsm_from_module_instance(
            &typed_module.module,
            instance,
            typed_module.protocol.clone(),
            connections,
        );
        cfsm_map.insert(instance.type_name.clone(), cfsm);
    };
    let Cfsm {
        module,
        initial,
        finals,
        fsm,
    } = cfsm_map.get(&instance.type_name).unwrap();
    let channel_substitutions = channel_substitutions(instance, &typed_module.module, connections);
    let fsm = apply_channel_substitutions_on_fsm(&channel_substitutions, fsm);
    Cfsm {
        module: module.clone(),
        initial: *initial,
        finals: finals.clone(),
        fsm,
    }
}

fn lookup_group_or_instantiate(
    typed_module: &TypedModule,
    instance: &ModuleInstance,
    connections: &Vec<Connect>,
    group_map: &mut HashMap<TypedModule, Group>,
) -> Group {
    if !group_map.contains_key(typed_module) {
        let mut group = Group::new();
        let cfsm = construct_cfsm_from_module_instance(
            &typed_module.module,
            instance,
            typed_module.protocol.clone(),
            connections,
        );
        group.insert(instance.clone(), cfsm);
        group_map.insert(typed_module.clone(), group);
    }
    let channel_substitutions = channel_substitutions(instance, &typed_module.module, connections);
    let mut group = Group::new();
    for (k, v) in group_map.get(typed_module).unwrap() {
        group.insert(k.clone(), Cfsm {
            module: v.module.clone(),
            initial: v.initial,
            finals: v.finals.clone(),
            fsm: apply_channel_substitutions_on_fsm(&channel_substitutions, &v.fsm),
        });
    }
    group
}

fn channel_substitutions(
    instance: &ModuleInstance,
    info: &ModuleInfo,
    connections: &[Connect],
) -> HashMap<Var, Channel> {
    let mut map = HashMap::new();
    info.ports.iter().enumerate().for_each(|(i, port)| {
        let r = connections
            .iter()
            .find(|c| c.module_instance == *instance && c.index == i);
        match r {
            None => None,
            Some(c) => map.insert(
                Var {
                    scope: info.module_name.clone(),
                    name: port.id.clone(),
                },
                c.channel.clone(),
            ),
        };
    });
    map
}

fn apply_channel_substitutions_on_fsm(
    channel_substitutions: &HashMap<Var, Channel>,
    fsm: &Fsm,
) -> Fsm {
    fsm.map(
        |_, n| n.clone(),
        |_, edge| edge.rebind_channel(channel_substitutions),
    )
}

fn retrieve_instance_in_scope(
    scope: &ModuleInfo,
    instances: &[ModuleInstance],
) -> Vec<ModuleInstance> {
    instances
        .iter()
        .filter(|i| i.scope.last().unwrap_or(&String::from("")).clone() == scope.module_name)
        .cloned()
        .collect()
}

fn retrieve_connect_in_scope(scope: &ModuleInfo, connections: &[Connect]) -> Vec<Connect> {
    connections
        .iter()
        .filter(|c| c.scope() == scope.module_name)
        .cloned()
        .collect()
}

fn dependency_tree_to_task_queue(tree: &DependencyTree) -> TaskQueue {
    let mut queue = TaskQueue::new();
    let root_id = tree.root_node_id().unwrap();
    for id in tree.traverse_post_order_ids(root_id).unwrap() {
        if let Ok(children) = tree.children(&id) {
            if children.count() > 0 {
                let parent = tree.get(&id).unwrap().data().clone();
                queue.push_back(parent);
            }
        }
    }
    queue
}
