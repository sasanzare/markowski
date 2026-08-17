#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if let Err(error) = markowski_desktop_shell_lib::run() {
        eprintln!("Markowski could not start: {error}");
        std::process::exit(1);
    }
}
