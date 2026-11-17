mod util;

fn main() {
    let bad: u32 = "not a number";
    println!("{} {}", util::greet("world"), bad);
}
