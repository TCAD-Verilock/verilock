use lazy_static::lazy_static;
use std::ffi::OsStr;
use std::path::PathBuf;

#[derive(Debug, PartialEq, Clone)]
pub struct ChannelIdentifier {
    pub channel_name: String,
    pub receive_name: String,
    pub send_name: String,
}

#[derive(Debug, PartialEq, Clone)]
pub struct Case {
    pub path: Box<PathBuf>,
    pub identifier: ChannelIdentifier,
}

impl Case {
    pub fn get_name(&self) -> Option<&str> {
        self.path.file_stem().and_then(OsStr::to_str)
    }
}

pub fn gen(index: usize) -> Case {
    Case {
        path: Box::new(PathBuf::from(format!("resources/gen/gen{}", index))),
        identifier: ID.clone(),
    }
}

lazy_static! {
    pub static ref ID: ChannelIdentifier = ChannelIdentifier {
        channel_name: "Channel".to_string(),
        receive_name: "Receive".to_string(),
        send_name: "Send".to_string()
    };
    pub static ref VC1: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case1/copy2")),
        identifier: ID.clone()
    };
    pub static ref VC1_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case1/copy2-d")),
        identifier: ID.clone()
    };
    pub static ref VC2: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case2/copy3")),
        identifier: ID.clone()
    };
    pub static ref VC2_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case2/copy3-d")),
        identifier: ID.clone()
    };
    pub static ref VC3: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case3/copy4")),
        identifier: ID.clone()
    };
    pub static ref VC3_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case3/copy4-d")),
        identifier: ID.clone()
    };
    pub static ref VC4: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case4/crc")),
        identifier: ID.clone()
    };
    pub static ref VC4_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case4/crc-d")),
        identifier: ID.clone()
    };
    pub static ref VC5: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case5/crc-env")),
        identifier: ID.clone()
    };
    pub static ref VC5_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case5/crc-env-d")),
        identifier: ID.clone()
    };
    pub static ref VC6: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case6/pipeline")),
        identifier: ID.clone()
    };
    pub static ref VC6_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case6/pipeline-d")),
        identifier: ID.clone()
    };
    pub static ref VC7: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case7/adder")),
        identifier: ID.clone()
    };
    pub static ref VC7_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case7/adder-d")),
        identifier: ID.clone()
    };
    pub static ref VC8: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case8/arv")),
        identifier: ID.clone()
    };
    pub static ref VC8_: Case = Case {
        path: Box::new(PathBuf::from("resources/cases/case8/arv-d")),
        identifier: ID.clone()
    };
    pub static ref EXPERIMENT1: Vec<Case> = vec!(
        VC1.clone(),
        VC2.clone(),
        VC3.clone(),
        VC4.clone(),
        VC5.clone(),
        VC6.clone(),
        VC7.clone(),
        VC8.clone(),
        VC1_.clone(),
        VC2_.clone(),
        VC3_.clone(),
        VC4_.clone(),
        VC5_.clone(),
        VC6_.clone(),
        VC7_.clone(),
        VC8_.clone(),
    );
    pub static ref EXPERIMENT2: Vec<Case> = (91..=100).map(gen).collect();
}
