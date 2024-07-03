use std::collections::{HashMap, HashSet, VecDeque};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::ops::Deref;
use std::sync::mpsc::{Receiver, TryRecvError};

use im::HashMap as IHashMap;
use im::Vector;
use petgraph::graph::{EdgeIndex, NodeIndex};
use petgraph::visit::EdgeRef;
use z3::Solver;

use crate::abstraction::protocol::Communication;
use crate::abstraction::sv_info::{BoolExpression, Channel, ModuleInfo, ModuleInstance};
use crate::cfsm::env::{Environment, ModifiableEnvironment};
use crate::cfsm::fsm::{AnonymousCFSM, BlankNode, Cfsm, EdgeInfo, Fsm};
use crate::error::{Action, DanglingReceiving, DanglingSending, LiveLock, VerilockError};
use crate::hash::HashCode;

type LocalStep = (ModuleInstance, NodeIndex, EdgeIndex);

#[derive(Debug, PartialEq, Clone)]
enum SynthesisStep {
    Jump(Jump),
    External(External),
    Match(Match),
}

#[derive(Debug, PartialEq, Clone)]
struct Jump {
    instance: ModuleInstance,
    source_id: NodeIndex,
    edge_id: EdgeIndex,
}

#[derive(Debug, PartialEq, Clone)]
struct External {
    instance: ModuleInstance,
    source_id: NodeIndex,
    edge_id: EdgeIndex,
}

#[derive(Debug, PartialEq, Clone)]
struct Match {
    send_instance: ModuleInstance,
    send_source: NodeIndex,
    send_edge: EdgeIndex,
    recv_instance: ModuleInstance,
    recv_source: NodeIndex,
    recv_edge: EdgeIndex,
}

#[derive(Debug, PartialEq, Clone, Eq, Hash)]
struct GlobalConfiguration {
    node: BlankNode,
    env: Environment,
}

// module instance -> local CFSM node index
type LocalConfigurations = IHashMap<ModuleInstance, NodeIndex>;

impl HashCode for LocalConfigurations {
    fn hashcode(&self) -> u64 {
        let mut s = DefaultHasher::new();
        self.hash(&mut s);
        s.finish()
    }
}

pub type Group = HashMap<ModuleInstance, Cfsm>;

#[derive(Debug, PartialEq, Clone)]
struct SynthesisState {
    local_configurations: LocalConfigurations,
    current_env: Environment,
    error_trace: Vector<Action>,
}

pub fn synthesize(
    group: Group,
    parent: ModuleInfo,
    solver: &Solver,
    solving_count: &mut i32,
    abort_receiver: &Receiver<()>
) -> Result<Cfsm, VerilockError> {
    let mut local_nodes_to_global_node = HashMap::<Vec<NodeIndex>, BlankNode>::new();
    let local_configurations = group
        .iter()
        .map(|(instance, cfsm)| (instance.clone(), cfsm.initial))
        .collect::<IHashMap<ModuleInstance, NodeIndex>>();
    let initial_synthesis_state = SynthesisState {
        local_configurations,
        current_env: Environment::new(),
        error_trace: Vector::new(),
    };
    let mut used_edges = HashSet::<(ModuleInstance, EdgeIndex)>::new();
    let mut fsm = Fsm::new();
    let mut initial_id: Option<NodeIndex> = None;
    let mut initial_node: Option<BlankNode> = None;
    let mut visited_global_configs = HashSet::new();
    let mut synthesis_queue = VecDeque::new();
    visited_global_configs.insert(synthesis_state_to_global_config(
        &initial_synthesis_state,
        &mut local_nodes_to_global_node,
    ));
    synthesis_queue.push_back(initial_synthesis_state);
    let mut global_node_reverse_map = HashMap::<BlankNode, NodeIndex>::new();
    while let Some(synthesis_state) = synthesis_queue.pop_front() {
        let SynthesisState {
            local_configurations,
            current_env,
            error_trace,
        } = synthesis_state;
        let source_node = retrieve_or_construct_node(
            &mut local_nodes_to_global_node,
            &local_configurations.values().cloned().collect(),
        );
        let source_id = find_index_by_weight_or_insert_node(&mut fsm, &mut global_node_reverse_map, source_node.clone());
        if initial_id.is_none() {
            initial_id = Some(source_id);
            initial_node = Some(source_node);
        }
        let synthesis_steps = generate_all_possible_synthesis_steps(
            &local_configurations,
            &current_env,
            solver,
            solving_count,
            &group,
            &error_trace,
        )?;
        for step in synthesis_steps {
            record_used_edges(&mut used_edges, &step);
            let next_configurations =
                next_local_configurations(&group, &local_configurations, &step);
            let next_node = retrieve_or_construct_node(
                &mut local_nodes_to_global_node,
                &next_configurations.values().cloned().collect(),
            );
            let target_id = find_index_by_weight_or_insert_node(&mut fsm, &mut global_node_reverse_map, next_node);
            let edge = step_to_edge_info(&group, &step);
            let next_env = modify_environment_by_edge(&edge, &current_env);
            fsm.add_edge(source_id, target_id, edge);
            let next_error_trace = record_error_trace(&error_trace, &step, &group);
            let next_synthesis_state = SynthesisState {
                local_configurations: next_configurations,
                current_env: next_env,
                error_trace: next_error_trace,
            };
            let next_global_config =
                synthesis_state_to_global_config(&next_synthesis_state, &mut local_nodes_to_global_node);
            // there are two situations that next synthesis state will not be explored:
            // 1. if the state has been visited;
            // 2. if all the CFSMs in the group are back to their initial states.
            if !visited_global_configs.contains(&next_global_config)
                && !return_to_initial_state(&initial_node, &next_global_config.node)
            {
                visited_global_configs.insert(next_global_config);
                synthesis_queue.push_back(next_synthesis_state);
            }
        }
        match abort_receiver.try_recv() {
            Ok(_) => return Err(VerilockError::Timeout),
            Err(TryRecvError::Empty) => {},
            Err(TryRecvError::Disconnected) => return Err(VerilockError::Timeout)
        }
    }
    if let Some(instance) = check_live_locked(&group, &used_edges) {
        return Err(VerilockError::LiveLock(LiveLock { module: instance }));
    }
    Ok(AnonymousCFSM {
        initial: initial_id.expect("missing initial node when synthesizing CFSMs"),
        finals: HashSet::new(),
        fsm,
    }.fold_jump())
        .map(|anonymous_fsm| Cfsm {
            module: parent,
            initial: anonymous_fsm.initial,
            finals: anonymous_fsm.finals,
            fsm: anonymous_fsm.fsm,
        })
}

fn return_to_initial_state(initial: &Option<BlankNode>, next_global_node: &BlankNode) -> bool {
    initial.is_some() && initial.as_ref().unwrap() == next_global_node
}

fn find_index_by_weight_or_insert_node(
    fsm: &mut Fsm,
    node_cache: &mut HashMap<BlankNode, NodeIndex>,
    node_weight: BlankNode
) -> NodeIndex {
    *node_cache.entry(node_weight.clone())
        .or_insert_with(|| fsm.add_node(node_weight))
        .deref()
}

fn check_live_locked(
    group: &Group,
    used: &HashSet<(ModuleInstance, EdgeIndex)>,
) -> Option<ModuleInstance> {
    for (instance, cfsm) in group {
        let edges: HashSet<(ModuleInstance, EdgeIndex)> = cfsm
            .fsm
            .edge_indices()
            .map(|e| (instance.clone(), e))
            .collect();
        // if a CFSM is not empty and its edges are not used in the synthesis CFSM
        if !edges.is_empty() && edges.intersection(used).count() == 0 {
            return Some(instance.clone());
        }
    }
    None
}

fn record_error_trace(old_trace: &Vector<Action>, step: &SynthesisStep, group: &Group) -> Vector<Action> {
    let mut trace = old_trace.clone();
    match step {
        SynthesisStep::Jump(j) => {
            trace.push_back(construct_action_description(
                &j.instance,
                j.edge_id,
                group,
            ));
        }
        SynthesisStep::External(e) => {
            trace.push_back(construct_action_description(
                &e.instance,
                e.edge_id,
                group,
            ));
        }
        SynthesisStep::Match(m) => {
            trace.push_back(construct_action_description(
                &m.send_instance,
                m.send_edge,
                group,
            ));
            trace.push_back(construct_action_description(
                &m.recv_instance,
                m.recv_edge,
                group,
            ));
        }
    };
    trace
}

fn synthesis_state_to_global_config(
    synthesis_state: &SynthesisState,
    local_nodes_to_global_node: &mut HashMap<Vec<NodeIndex>, BlankNode>,
) -> GlobalConfiguration {
    GlobalConfiguration {
        node: retrieve_or_construct_node(
            local_nodes_to_global_node,
            &synthesis_state
                .local_configurations
                .values()
                .cloned()
                .collect(),
        ),
        env: synthesis_state.current_env.clone(),
    }
}

fn modify_environment_by_edge(edge_info: &EdgeInfo, current_env: &Environment) -> Environment {
    if edge_info.guard.is_none() && edge_info.updates.is_empty() {
        return current_env.clone();
    }
    let mut next_env = Environment::new();
    if let Some(g) = &edge_info.guard {
        next_env = next_env.extend_env(g);
    }
    for u in &edge_info.updates {
        next_env = next_env.update_env(u);
    }
    next_env
}

fn step_to_edge_info(group: &Group, step: &SynthesisStep) -> EdgeInfo {
    match step {
        SynthesisStep::Jump(j) => group
            .get(&j.instance)
            .unwrap()
            .fsm
            .edge_weight(j.edge_id)
            .unwrap()
            .clone(),
        SynthesisStep::External(e) => group
            .get(&e.instance)
            .unwrap()
            .fsm
            .edge_weight(e.edge_id)
            .unwrap()
            .clone(),
        SynthesisStep::Match(m) => {
            let s_edge = group
                .get(&m.send_instance)
                .unwrap()
                .fsm
                .edge_weight(m.send_edge)
                .unwrap();
            let r_edge = group
                .get(&m.recv_instance)
                .unwrap()
                .fsm
                .edge_weight(m.recv_edge)
                .unwrap();
            let merged_guard = merge_guard(s_edge.guard.clone(), r_edge.guard.clone());
            let mut merged_updates = s_edge.updates.clone();
            merged_updates.extend(r_edge.updates.clone());
            EdgeInfo {
                communication: None,
                guard: merged_guard,
                updates: merged_updates,
            }
        }
    }
}

fn merge_guard(
    s_guard: Option<BoolExpression>,
    r_guard: Option<BoolExpression>,
) -> Option<BoolExpression> {
    if s_guard.is_some() && r_guard.is_some() {
        let s_guard = s_guard.unwrap();
        let r_guard = r_guard.unwrap();
        Some(BoolExpression::And(Box::new(s_guard), Box::new(r_guard)))
    } else if s_guard.is_some() {
        s_guard
    } else {
        r_guard
    }
}

fn record_used_edges(used_edges: &mut HashSet<(ModuleInstance, EdgeIndex)>, 
                     step: &SynthesisStep) {
    match step {
        SynthesisStep::Jump(j) => {
            used_edges.insert((j.instance.clone(), j.edge_id));
        }
        SynthesisStep::External(e) => {
            used_edges.insert((e.instance.clone(), e.edge_id));
        }
        SynthesisStep::Match(m) => {
            used_edges.insert((m.send_instance.clone(), m.send_edge));
            used_edges.insert((m.recv_instance.clone(), m.recv_edge));
        }
    }
}

fn next_local_configurations(
    group: &Group,
    current: &LocalConfigurations,
    step: &SynthesisStep,
) -> LocalConfigurations {
    match step {
        SynthesisStep::Jump(j) => {
            current.update(
                j.instance.clone(),
                retrieve_next_node(group, &j.instance, j.edge_id),
            )
        }
        SynthesisStep::External(e) => {
            current.update(
                e.instance.clone(),
                retrieve_next_node(group, &e.instance, e.edge_id),
            )
        }
        SynthesisStep::Match(m) => {
            current.update(
                m.send_instance.clone(),
                retrieve_next_node(group, &m.send_instance, m.send_edge),
            ).update(
                m.recv_instance.clone(),
                retrieve_next_node(group, &m.recv_instance, m.recv_edge),
            )
        }
    }
}

fn retrieve_next_node(group: &Group, instance: &ModuleInstance, edge_id: EdgeIndex) -> NodeIndex {
    let (_, t) = &group
        .get(instance)
        .unwrap()
        .fsm
        .edge_endpoints(edge_id)
        .unwrap();
    *t
}

fn generate_all_possible_synthesis_steps(
    local_configurations: &LocalConfigurations,
    current_env: &Environment,
    solver: &Solver,
    solving_count: &mut i32,
    group: &Group,
    error_trace: &Vector<Action>,
) -> Result<Vec<SynthesisStep>, VerilockError> {
    let mut synthesis_steps = Vec::new();
    let (jumps, externals, sendings, receivings) =
        all_possible_local_steps(local_configurations, group, current_env, solver, solving_count);
    for (cfsm_name, source_id, edge_id) in jumps
    {
        synthesis_steps.push(SynthesisStep::Jump(Jump {
            instance: cfsm_name,
            source_id,
            edge_id,
        }))
    }
    for (cfsm_name, source_id, edge_id) in externals
    {
        synthesis_steps.push(SynthesisStep::External(External {
            instance: cfsm_name,
            source_id,
            edge_id,
        }))
    }
    for (s_name, s_source_id, s_edge_id) in sendings.iter() {
        for (r_name, r_source_id, r_edge_id) in receivings.iter() {
            let s_channel = retrieve_channel_from_map(s_name, *s_edge_id, group);
            let r_channel = retrieve_channel_from_map(r_name, *r_edge_id, group);
            // from two different cfsms and through the same channel
            if s_name != r_name && s_channel == r_channel {
                synthesis_steps.push(SynthesisStep::Match(Match {
                    send_instance: s_name.clone(),
                    send_source: *s_source_id,
                    send_edge: *s_edge_id,
                    recv_instance: r_name.clone(),
                    recv_source: *r_source_id,
                    recv_edge: *r_edge_id,
                }));
            }
        }
    }
    if synthesis_steps.is_empty() {
        if let Some((name, _, edge_id)) = sendings.first() {
            return Err(VerilockError::DanglingSending(DanglingSending {
                trace: error_trace.clone(),
                dangling: construct_action_description(name, *edge_id, group),
            }));
        }
        if let Some((name, _, edge_id)) = receivings.first() {
            return Err(VerilockError::DanglingReceiving(DanglingReceiving {
                trace: error_trace.clone(),
                dangling: construct_action_description(name, *edge_id, group),
            }));
        }
    }
    Ok(synthesis_steps)
}

fn retrieve_channel_from_map(
    instance: &ModuleInstance,
    edge_id: EdgeIndex,
    group: &Group,
) -> Channel {
    group
        .get(instance)
        .expect("CFSM not found")
        .fsm
        .edge_weight(edge_id)
        .expect("edge not found")
        .communication
        .as_ref()
        .expect("communication not found")
        .channel()
}

fn construct_action_description(
    instance: &ModuleInstance,
    edge_id: EdgeIndex,
    group: &Group,
) -> Action {
    Action {
        subject: instance.clone(),
        action: group
            .get(instance)
            .expect("CFSM not found")
            .fsm
            .edge_weight(edge_id)
            .expect("edge not found")
            .describe(),
    }
}

fn all_possible_local_steps(
    local_configurations: &LocalConfigurations,
    group:&Group,
    env: &Environment,
    solver: &Solver,
    solving_count: &mut i32
) -> (Vec<LocalStep>, Vec<LocalStep>, Vec<LocalStep>, Vec<LocalStep>) {
    let mut jumps = Vec::new();
    let mut externals = Vec::new();
    let mut internal_sendings = Vec::new();
    let mut internal_receivings = Vec::new();
    for (cfsm_name, node_index) in local_configurations {
        let cfsm = group.get(cfsm_name).unwrap();
        for edge_ref in cfsm.fsm.edges(*node_index) {
            let edge = edge_ref.weight();
            let satisfiable = if edge.guard.is_none() && edge.updates.is_empty() {
                true
            } else {
                let extended_env = modify_environment_by_edge(edge, env);
                *solving_count += 1;
                extended_env.satisfiable(solver).unwrap_or_else(|e| {
                    e.report();
                    false
                })
            };
            if satisfiable {
                let edge_id = edge_ref.id();
                if let Some(c) = &edge.communication {
                    if c.is_external() {
                        externals.push((cfsm_name.clone(), *node_index, edge_id));
                    } else if matches!(c, Communication::Send(_)) {
                        internal_sendings.push((cfsm_name.clone(), *node_index, edge_id));
                    } else {
                        internal_receivings.push((cfsm_name.clone(), *node_index, edge_id));
                    }
                } else {
                    jumps.push((cfsm_name.clone(), *node_index, edge_id));
                }
            }
        }
    }
    (jumps, externals, internal_sendings, internal_receivings)
}

fn retrieve_or_construct_node(
    node_map: &mut HashMap<Vec<NodeIndex>, BlankNode>,
    nodes: &Vec<NodeIndex>,
) -> BlankNode {
    if node_map.contains_key(nodes) {
        node_map.get(nodes).unwrap().clone()
    } else {
        let new_node = BlankNode::new();
        node_map.insert(nodes.clone(), new_node.clone());
        new_node
    }
}
