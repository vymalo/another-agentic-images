package main

import "fmt"

func main() {
	var bad int = "not a number"
	fmt.Println(greet("world"), bad)
}
