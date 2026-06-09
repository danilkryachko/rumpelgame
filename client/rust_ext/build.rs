use std::env;
use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    
    prost_build::Config::new()
        .out_dir(&out_dir)
        .compile_protos(&["../../api/schema/packets.proto"], &["../../api/schema"])
        .unwrap_or_else(|e| panic!("Failed to compile protobuf files: {}", e));
        
    println!("cargo:rerun-if-changed=../../api/schema/packets.proto");
}
