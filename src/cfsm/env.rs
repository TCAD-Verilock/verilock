use std::hash::{DefaultHasher, Hash, Hasher};
use crate::abstraction::protocol::Update;
use crate::abstraction::sv_info::{BinRel, BoolExpression, Primary};
use crate::error::{UnsolvableConstraints, VerilockError};
use im::{HashSet};
use std::collections::{HashMap};
use std::sync::Mutex;
use lazy_static::lazy_static;
use z3::ast::Ast;
use z3::{ast, Context, SatResult, Solver};
use crate::hash::HashCode;

lazy_static!(
  static ref CACHE: Mutex<HashMap<u64, bool>> = Mutex::new(HashMap::new());
);

fn get_cached_value(key: &u64) -> Option<bool> {
    let cache = CACHE.lock().unwrap();
    cache.get(key).cloned()
}

fn insert_cache(key: u64, value: bool) {
    let mut cache = CACHE.lock().unwrap();
    cache.insert(key, value);
}

pub type Environment = HashSet<BoolExpression>;

pub trait ModifiableEnvironment {
    fn extend_env(&self, e: &BoolExpression) -> Self;
    fn update_env(&self, u: &Update) -> Self;
    fn satisfiable(&self, solver: &Solver) -> Result<bool, VerilockError>;
}

impl HashCode for Environment {
    fn hashcode(&self) -> u64 {
        let mut s = DefaultHasher::new();
        self.hash(&mut s);
        s.finish()
    }
}

impl ModifiableEnvironment for Environment {
    fn extend_env(&self, e: &BoolExpression) -> Environment {
        if e == &BoolExpression::True || e == &BoolExpression::Unknown {
            return self.clone();
        }
        if e == &BoolExpression::False {
            return HashSet::new().update(BoolExpression::False);
        }
        self.update(e.clone())
    }

    fn update_env(&self, u: &Update) -> Environment {
        let old_env: HashSet<BoolExpression> = self
            .iter()
            .map(|e| e.invalidate_and_rebind_var(&u.var))
            .collect();
        old_env.update(BoolExpression::Binary(
            Primary::Variable(u.var.clone()),
            BinRel::Eq,
            u.primary.clone(),
        ))
    }

    fn satisfiable(&self, solver: &Solver) -> Result<bool, VerilockError> {
        let hash = self.hashcode();
        if let Some(cached) = get_cached_value(&hash) {
            Ok(cached)
        } else {
            solver.push();
            let ctx = solver.get_context();
            for e in self {
                solver.assert(&encode_bool_expression(ctx, e));
            }
            match solver.check() {
                SatResult::Unsat => {
                    solver.pop(1);
                    insert_cache(hash, false);
                    Ok(false)
                }
                SatResult::Unknown => {
                    solver.pop(1);
                    insert_cache(hash, false);
                    Err(VerilockError::UnsolvableConstraints(
                        UnsolvableConstraints {
                            constraints: solver
                                .get_assertions()
                                .iter()
                                .map(|c| c.to_string())
                                .collect(),
                        },
                    ))
                }
                SatResult::Sat => {
                    solver.pop(1);
                    insert_cache(hash, true);
                    Ok(true)
                }
            }
        }
    }
}

fn encode_bool_expression<'a>(ctx: &'a Context, e: &BoolExpression) -> ast::Bool<'a> {
    match e {
        BoolExpression::True => ast::Bool::from_bool(ctx, true),
        BoolExpression::False => ast::Bool::from_bool(ctx, false),
        BoolExpression::Unknown => ast::Bool::from_bool(ctx, true),
        BoolExpression::Binary(l, op, r) => {
            let l = encode_primary(ctx, l);
            let r = encode_primary(ctx, r);
            if l.is_none() || r.is_none() {
                ast::Bool::from_bool(ctx, true)
            } else {
                let l = l.unwrap();
                let r = r.unwrap();
                match op {
                    BinRel::Eq => l._eq(&r),
                    BinRel::NotEq => l._eq(&r).not(),
                    BinRel::Gt => l.gt(&r),
                    BinRel::Lt => l.lt(&r),
                    BinRel::Ge => l.ge(&r),
                    BinRel::Le => l.le(&r),
                }
            }
        }
        BoolExpression::Not(sub) => encode_bool_expression(ctx, sub).not(),
        BoolExpression::And(l, r) => ast::Bool::and(
            ctx,
            &[
                &encode_bool_expression(ctx, l),
                &encode_bool_expression(ctx, r),
            ],
        ),
        BoolExpression::Or(l, r) => ast::Bool::or(
            ctx,
            &[
                &encode_bool_expression(ctx, l),
                &encode_bool_expression(ctx, r),
            ],
        ),
    }
}

fn encode_primary<'a>(ctx: &'a Context, p: &Primary) -> Option<ast::Int<'a>> {
    match p {
        Primary::Variable(v) => Some(ast::Int::new_const(ctx, format!("{}.{}", v.scope, v.name))),
        Primary::Int(i) => Some(ast::Int::from_i64(ctx, *i as i64)),
        Primary::Unknown => None,
    }
}
