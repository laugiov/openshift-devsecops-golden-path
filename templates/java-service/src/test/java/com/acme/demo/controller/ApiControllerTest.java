package com.acme.demo.controller;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class ApiControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void healthEndpointReturnsOk() throws Exception {
        mockMvc.perform(get("/api/health"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.status").value("healthy"))
               .andExpect(jsonPath("$.service").value("java-demo-service"));
    }

    @Test
    void readyEndpointReturnsOk() throws Exception {
        mockMvc.perform(get("/api/ready"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.status").value("ready"));
    }

    @Test
    void infoEndpointReturnsServiceInfo() throws Exception {
        mockMvc.perform(get("/api/info"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.name").value("java-demo-service"))
               .andExpect(jsonPath("$.stack").exists());
    }
}
