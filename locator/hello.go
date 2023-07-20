package RedpandaLocatorCF

import (
	"log"
	"net/http"
)

//func init() {
//	functions.HTTP("hello", Hello)
//}

func Hello(w http.ResponseWriter, r *http.Request) {
	log.SetOutput(w)
	log.Println("hello")
}
