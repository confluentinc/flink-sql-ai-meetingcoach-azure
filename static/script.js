// Meeting Coach Demo - Front-end JavaScript

// Global state
const state = {
    meetingData: [],
    currentMessageIndex: -1,
    autoPlayInterval: null,
    autoPlaySpeed: 3500, // milliseconds (increased from 2000)
    customMessages: [], // For storing user-input messages
    cachedQuestions: [] // For storing cached Q&A pairs
};

// DOM Elements
const conversationContainer = document.getElementById('conversation-container');
const coachingContainer = document.getElementById('coaching-container');
const resetBtn = document.getElementById('reset-btn');
const autoPlayBtn = document.getElementById('auto-play-btn');
const chatInput = document.getElementById('chat-input');
const sendBtn = document.getElementById('send-btn');
const suggestedQuestionsContainer = document.getElementById('suggested-questions-container');
const themeToggleBtn = document.getElementById('theme-toggle');
// Cache Manager Modal Elements
const cacheManagerModal = document.getElementById('cache-manager-modal');
const closeCacheModalBtn = document.getElementById('close-cache-modal');
const cachedItemsTableBody = document.getElementById('cached-items-table-body');
const addCacheForm = document.getElementById('add-cache-form');
const newCacheQuestionInput = document.getElementById('new-cache-question');
const newCacheResponseInput = document.getElementById('new-cache-response');

// Typing indicator will be created dynamically
let typingIndicator = null;
let bootstrapCacheModal = null; // Variable for Bootstrap modal instance

// Fetch meeting data when page loads
document.addEventListener('DOMContentLoaded', () => {
    fetchMeetingData();
    fetchCachedQuestions(); // Fetch cached questions
    setupEventListeners();

    // Initialize WebSocket for real-time coaching advice
    initializeCoachingWebSocket();

    // Create typing indicator element
    createTypingIndicator();

    // Initialize theme based on localStorage
    initializeTheme();

    // Add listener for quick save shortcut (Ctrl+Shift+C)
    document.addEventListener('keydown', handleQuickSaveShortcut);
    // Add listener for Cache Manager shortcut (Ctrl+Shift+M)
    document.addEventListener('keydown', handleCacheManagerShortcut);

    // Initialize Bootstrap modal for Cache Manager
    const cacheModalElement = document.getElementById('cache-manager-modal');
    if (cacheModalElement) {
        try {
            // Make sure Bootstrap is fully loaded before initializing
            if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
                bootstrapCacheModal = new bootstrap.Modal(cacheModalElement);
                console.log("Bootstrap cache modal initialized successfully");
            } else {
                console.error("Bootstrap library not loaded correctly");
                // Set a fallback timeout to try again after Bootstrap loads
                setTimeout(() => {
                    if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
                        bootstrapCacheModal = new bootstrap.Modal(cacheModalElement);
                        console.log("Bootstrap cache modal initialized on retry");
                    }
                }, 1000);
            }
        } catch (error) {
            console.error("Error initializing Bootstrap modal:", error);
        }
    } else {
        console.error("Cache Manager modal element not found!");
    }
});

// Create the typing indicator element
function createTypingIndicator() {
    typingIndicator = document.createElement('div');
    typingIndicator.className = 'message message-salesperson typing-indicator';
    typingIndicator.style.display = 'none';
    typingIndicator.innerHTML = `
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
        <div class="typing-dot"></div>
    `;
}

// Show typing indicator at the bottom of the conversation
function showTypingIndicator() {
    if (!typingIndicator) {
        createTypingIndicator();
    }

    // Remove it if it's already in the DOM (to reposition it at the end)
    if (typingIndicator.parentNode) {
        typingIndicator.parentNode.removeChild(typingIndicator);
    }

    // Add it to the end of the conversation container
    conversationContainer.appendChild(typingIndicator);
    typingIndicator.style.display = 'flex';
    scrollToBottom();
}

// Hide typing indicator
function hideTypingIndicator() {
    if (typingIndicator) {
        typingIndicator.style.display = 'none';
    }
}

// Setup event listeners
function setupEventListeners() {
    resetBtn.addEventListener('click', resetConversation);
    autoPlayBtn.addEventListener('click', toggleAutoPlay);

    // Chat input handlers
    sendBtn.addEventListener('click', sendChatMessage);
    chatInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            sendChatMessage();
        }
    });

    // Event delegation for suggested response clicks has been removed
    // The response is already added automatically to the conversation
    // This allows users to select/copy the text without triggering any action

    // Theme toggle handler
    if (themeToggleBtn) {
        themeToggleBtn.addEventListener('click', toggleDarkMode);
    }

    // Cache Management Button Handlers
    const saveCacheBtn = document.getElementById('save-cache-btn');
    if (saveCacheBtn) {
        // Initially disable and hide save button until there's content to save
        saveCacheBtn.style.opacity = '0.4';
        saveCacheBtn.disabled = true;

        saveCacheBtn.addEventListener('click', function() {
            if (window.lastUserQuestion && window.lastCoachingData) {
                // Use the lastCoachingData to cache the interaction
                const dataToCache = {
                    question: window.lastUserQuestion,
                    response: window.lastCoachingData.response,
                    coaching_data: {
                        reasoning: window.lastCoachingData.reasoning || '',
                        used_excerpts: window.lastCoachingData.used_excerpts || '',
                        rag_sources: window.lastCoachingData.rag_sources || '',
                        knowledge: window.lastCoachingData.knowledge || ''
                    }
                };

                // Use the cache_interaction endpoint to save the data
                fetch('/cache_interaction', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(dataToCache)
                })
                .then(response => response.json())
                .then(result => {
                    if (result.status === 'success') {
                        alert("Response saved successfully! It will now appear in suggested questions.");
                        // Refresh suggested questions
                        if (!state.cachedQuestions.some(q => q.question === result.question)) {
                            state.cachedQuestions.push({
                                question: window.lastUserQuestion,
                                Response: window.lastCoachingData.response,
                                Reasoning: window.lastCoachingData.reasoning || '',
                                "Used Excerpts": window.lastCoachingData.used_excerpts || '',
                                "RAG sources": window.lastCoachingData.rag_sources || '',
                                Knowledge: window.lastCoachingData.knowledge || ''
                            });
                            displaySuggestedQuestions();
                        }
                    } else {
                        console.error("Failed to save response:", result);
                        alert("Failed to save response. Please try again.");
                    }
                })
                .catch(error => {
                    console.error("Error saving response:", error);
                    alert("Error saving response: " + error.message);
                });
            } else {
                alert("No response available to save. Please ask a question first.");
            }
        });
    }

    const manageCacheBtn = document.getElementById('manage-cache-btn');
    if (manageCacheBtn) {
        // Enable manage cache button
        manageCacheBtn.style.opacity = '1';
        manageCacheBtn.disabled = false;

        manageCacheBtn.addEventListener('click', openCacheManager);
    }

    // Cache Manager listeners
    if (closeCacheModalBtn) {
        closeCacheModalBtn.addEventListener('click', closeCacheManager);
    }
    if (cacheManagerModal) {
        // Close modal if clicking on the background
        cacheManagerModal.addEventListener('click', (event) => {
            if (event.target === cacheManagerModal) {
                closeCacheManager();
            }
        });
    }
    if (cachedItemsTableBody) {
        // Event delegation for delete buttons
        cachedItemsTableBody.addEventListener('click', handleDeleteCacheItem);
    }
    if (addCacheForm) {
        addCacheForm.addEventListener('submit', handleAddCacheItem);
    }

}

// Initialize theme based on localStorage
function initializeTheme() {
    // Check if user has a saved preference
    const darkModeEnabled = localStorage.getItem('darkMode') === 'enabled';

    if (darkModeEnabled) {
        document.body.classList.add('dark-mode');
        updateThemeToggleIcon(true);
    }
}

// Toggle dark mode
function toggleDarkMode() {
    const isDarkMode = document.body.classList.toggle('dark-mode');

    // Save preference to localStorage
    localStorage.setItem('darkMode', isDarkMode ? 'enabled' : 'disabled');

    // Update the icon
    updateThemeToggleIcon(isDarkMode);
}

// Update the theme toggle icon based on current mode
function updateThemeToggleIcon(isDarkMode) {
    if (!themeToggleBtn) return;

    const icon = themeToggleBtn.querySelector('i');
    if (icon) {
        if (isDarkMode) {
            icon.classList.remove('fa-moon');
            icon.classList.add('fa-sun');
        } else {
            icon.classList.remove('fa-sun');
            icon.classList.add('fa-moon');
        }
    }
}

// WebSocket for real-time coaching advice
let coachingSocket;

function initializeCoachingWebSocket() {
    // Get the hostname and port from the current URL
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host;

    // Connect to WebSocket endpoint
    coachingSocket = new WebSocket(`${protocol}//${host}/ws/coaching`);

    coachingSocket.onopen = () => {
        console.log('Coaching WebSocket connection established');
    };

    coachingSocket.onmessage = (event) => {
        const coaching = JSON.parse(event.data);
        displayRealTimeCoachingAdvice(coaching);
    };

    coachingSocket.onclose = () => {
        console.log('Coaching WebSocket connection closed');
        // Try to reconnect after 5 seconds
        setTimeout(initializeCoachingWebSocket, 5000);
    };

    coachingSocket.onerror = (error) => {
        console.error('WebSocket error:', error);
    };
}

// Fetch meeting data from API
async function fetchMeetingData() {
    try {
        const response = await fetch('/api/meeting-data');
        if (!response.ok) {
            throw new Error('Failed to fetch meeting data');
        }
        state.meetingData = await response.json();
    } catch (error) {
        console.error('Error fetching meeting data:', error);
        showError('Failed to load meeting data. Please try refreshing the page.');
    }
}

// Fetch cached questions from API
async function fetchCachedQuestions() {
    try {
        console.log("Fetching cached questions from API...");
        const response = await fetch('/api/cached-questions');

        if (!response.ok) {
            throw new Error(`Failed to fetch cached questions: ${response.status} ${response.statusText}`);
        }

        let questions = await response.json();
        console.log("Received cached questions:", questions);

        // Handle empty response
        if (!questions || !Array.isArray(questions)) {
            console.warn("API returned invalid or empty questions data:", questions);
            questions = [];
        }

        // Process each question to ensure required fields
        state.cachedQuestions = questions
            .filter(item => {
                // Filter out items without both question/Message and Response/response
                return (item.question || item.Message) &&
                       (item.Response || item.response);
            })
            .map(item => {
                // Ensure both Message/Response and question/response formats are considered
                // Create a consistent object structure for the frontend
                return {
                    question: item.question || item.Message || '',
                    Response: item.Response || item.response || '',
                    Reasoning: item.Reasoning || '',
                    "Used Excerpts": item["Used Excerpts"] || '',
                    "RAG sources": item["RAG sources"] || '',
                    Knowledge: item.Knowledge || ''
                };
            });

        console.log(`Processed ${state.cachedQuestions.length} cached questions`);
        displaySuggestedQuestions(); // Display questions after fetching
    } catch (error) {
        console.error('Error fetching cached questions:', error);

        // Try to recover by loading from the alternate endpoint
        try {
            console.log("Attempting to fetch from fallback endpoint /cached_responses");
            const fallbackResponse = await fetch('/cached_responses');
            if (fallbackResponse.ok) {
                let fallbackQuestions = await fallbackResponse.json();

                // Process the fallback data to the format we need
                state.cachedQuestions = fallbackQuestions
                    .filter(item => {
                        // Filter out items without both question/Message and Response/response
                        return (item.question || item.Message) &&
                               (item.Response || item.response);
                    })
                    .map(item => {
                        return {
                            question: item.question || item.Message || '',
                            Response: item.Response || item.response || '',
                            Reasoning: item.Reasoning || '',
                            "Used Excerpts": item["Used Excerpts"] || '',
                            "RAG sources": item["RAG sources"] || '',
                            Knowledge: item.Knowledge || ''
                        };
                    });

                console.log(`Recovered ${state.cachedQuestions.length} questions from fallback endpoint`);
                displaySuggestedQuestions();
                return;
            }
        } catch (fallbackError) {
            console.error("Fallback fetch also failed:", fallbackError);
        }

        // If we reach here, both attempts failed
        if (suggestedQuestionsContainer) {
            suggestedQuestionsContainer.innerHTML = '<p class="text-muted text-center">Could not load suggested questions.</p>';
        }
    }
}

// Display suggested questions as buttons
function displaySuggestedQuestions() {
    if (!suggestedQuestionsContainer) {
        console.warn("suggestedQuestionsContainer not found in DOM");
        return;
    }

    // Check if we have any cached questions
    if (!state.cachedQuestions || !Array.isArray(state.cachedQuestions) || state.cachedQuestions.length === 0) {
        suggestedQuestionsContainer.innerHTML = '<p class="text-muted text-center">No suggested questions available.</p>';
        return;
    }

    // Filter out any incomplete items
    const validQuestions = state.cachedQuestions.filter(item => {
        return item &&
               item.question && // Require question to be non-empty
               item.Response && // Require Response to be non-empty
               typeof item.question === 'string' &&
               typeof item.Response === 'string';
    });

    if (validQuestions.length === 0) {
        suggestedQuestionsContainer.innerHTML = '<p class="text-muted text-center">No valid suggested questions found.</p>';
        return;
    }

    console.log(`Displaying ${Math.min(validQuestions.length, 3)} of ${validQuestions.length} valid questions`);
    suggestedQuestionsContainer.innerHTML = ''; // Clear previous buttons

    // Shuffle and select up to 3 questions
    const shuffled = [...validQuestions].sort(() => 0.5 - Math.random());
    const selectedQuestions = shuffled.slice(0, 3); // Limit to 3 suggestions

    selectedQuestions.forEach(item => {
        try {
            const button = document.createElement('button');
            button.className = 'btn btn-outline-info btn-sm m-1 suggested-question-btn';
            button.textContent = item.question;
            button.dataset.question = item.question; // Store question in data attribute

            // Sanitize the item to ensure it doesn't have any undefined/null values
            // that would cause JSON.stringify to fail
            const sanitizedItem = {};
            Object.entries(item).forEach(([key, value]) => {
                sanitizedItem[key] = value !== null && value !== undefined ? value : '';
            });

            try {
                // Wrap JSON.stringify in try/catch to catch circular reference errors
                button.dataset.fullData = JSON.stringify(sanitizedItem);
            } catch (jsonError) {
                console.error("Error stringifying item data:", jsonError);
                // Create a minimal safe version if JSON fails
                button.dataset.fullData = JSON.stringify({
                    question: item.question,
                    Response: item.Response
                });
            }

            button.addEventListener('click', handleSuggestedQuestionClick);
            suggestedQuestionsContainer.appendChild(button);
        } catch (error) {
            console.error("Error creating question button:", error, item);
        }
    });
}

// Handle click on a suggested question button
function handleSuggestedQuestionClick(event) {
    const button = event.target;
    const question = button.dataset.question;

    // Parse the full data with error handling
    let fullData;
    try {
        fullData = JSON.parse(button.dataset.fullData);
        // Validate that we have the minimum required fields
        if (!fullData.question || !fullData.Response) {
            throw new Error("Missing required fields in cached data");
        }
    } catch (error) {
        console.error("Error parsing button data:", error);
        alert("There was an error processing this question. Please try another one.");
        return;
    }

    // 1. Add question to chat immediately
    addMessageToConversation({
        message_id: `suggested-${Date.now()}`,
        speaker: 'Prospect', // User (Prospect) is asking the question
        message: question,
        meeting_id: 'suggested-interaction',
        timestamp: new Date().toISOString()
    });
    scrollToBottom();

    // Disable button temporarily to prevent double clicks
    button.disabled = true;
    button.textContent = 'Processing...';

    // Show typing indicator to indicate response is coming
    showTypingIndicator();

    // 2. After 3 seconds, display the full cached data in coaching section
    setTimeout(() => {
        try {
            displayCachedCoachingResponse(fullData);

            // 3. Rotate displayed questions
            displaySuggestedQuestions();
        } catch (error) {
            console.error("Error displaying cached response:", error);
            hideTypingIndicator();

            // Show a simplified response in case of error
            addMessageToConversation({
                speaker: "Salesperson",
                message: fullData.Response || "I'm sorry, I couldn't retrieve the cached response.",
                timestamp: new Date().toISOString()
            });

            // Also refresh questions
            displaySuggestedQuestions();
        }
    }, 3000); // 3 seconds delay for faster response
}


// Display a cached response in the coaching panel
function displayCachedCoachingResponse(fullData) {
    // Hide typing indicator
    hideTypingIndicator();

    // Hide the initial message if it exists
    const initialMessage = coachingContainer.querySelector('.initial-message');
    if (initialMessage) {
        initialMessage.style.display = 'none';
    }

    // Remove previous advice
    const prevAdvice = coachingContainer.querySelector('.coaching-advice');
    if (prevAdvice) {
        coachingContainer.removeChild(prevAdvice);
    }

    const adviceElement = document.createElement('div');
    adviceElement.className = 'coaching-advice new-advice'; // Use 'new-advice' for consistent animation

    // Remove the wrapper div by not adding the header
    let adviceHTML = ``;

    // According to CLAUDE.md, there should be two main headings:
    // 1. SUGGESTED RESPONSE
    // 2. KNOWLEDGE

    // Add the main response using the 'suggested-response' style
    adviceHTML += `
        <div class="coaching-section section-suggested-response">
            <div class="section-icon-container"><i class="fas fa-magic"></i></div>
            <div class="section-content-container">
                <h5>SUGGESTED RESPONSE</h5>
                <p>${fullData.Response}</p>
            </div>
        </div>
    `;

    // Add Knowledge section if available - this is specifically mentioned in CLAUDE.md #3
    if (fullData.Knowledge) {
        adviceHTML += `
        <div class="coaching-section section-knowledge">
            <div class="section-icon-container"><i class="fas fa-book"></i></div>
            <div class="section-content-container">
                <h5>KNOWLEDGE</h5>
                <p>${fullData.Knowledge}</p>
            </div>
        </div>`;
    }

    // Add reasoning if available - kept as an additional section
    if (fullData.Reasoning) {
        adviceHTML += `
        <div class="coaching-section section-reasoning">
            <div class="section-icon-container"><i class="fas fa-brain"></i></div>
            <div class="section-content-container">
                <h5>REASONING</h5>
                <p>${fullData.Reasoning}</p>
            </div>
        </div>`;
    }

    // Add used excerpts if available (renamed as requested)
    if (fullData["Used Excerpts"]) {
        try {
            // Try to parse the Used Excerpts as markdown
            if (fullData["Used Excerpts"]) {
                adviceHTML += `
                <div class="coaching-section section-used-excerpts">
                     <div class="section-icon-container"><i class="fas fa-file-alt"></i></div>
                     <div class="section-content-container">
                        <h5>RELEVANT EXCERPTS FROM RETRIEVED DOCUMENTS</h5>
                        <div>${marked.parse(fullData["Used Excerpts"])}</div>
                    </div>
                </div>`;
            }
        } catch (error) {
             console.error("Error processing Used Excerpts (cached):", error);
             adviceHTML += `
             <div class="coaching-section section-used-excerpts">
                 <div class="section-icon-container"><i class="fas fa-file-alt"></i></div>
                 <div class="section-content-container">
                    <h5>RELEVANT EXCERPTS FROM RETRIEVED DOCUMENTS</h5>
                    <p>${fullData["Used Excerpts"]}</p>
                 </div>
             </div>`;
        }
    }

    // Add RAG sources if available
    if (fullData["RAG sources"]) {
        try {
            // Try to parse the RAG sources as JSON
            let ragSources = fullData["RAG sources"];
            let parsedSources;

            if (typeof ragSources === 'string') {
                parsedSources = JSON.parse(ragSources);
            } else {
                parsedSources = ragSources;
            }

            adviceHTML += `<div class="coaching-section section-rag-sources">
                <div class="section-icon-container"><i class="fas fa-database"></i></div>
                <div class="section-content-container">
                    <h5>RAG SOURCES</h5>`;

            if (Array.isArray(parsedSources)) {
                parsedSources.forEach(source => {
                    const previewText = source.full_text.substring(0, 100) + '...';

                    adviceHTML += `
                    <div class="source-item">
                        <div class="source-header">
                            <a href="#" class="source-link" data-path="${source.title}">${source.title}</a>
                        </div>
                        <div class="source-preview">${previewText}</div>
                        <button class="btn btn-sm btn-outline-secondary expand-source-btn"
                                data-source-index="${source.document_index}">
                            Expand to view full text
                        </button>
                        <div class="source-full-text" id="source-full-text-${source.document_index}" style="display: none;">
                            ${marked.parse(source.full_text)}
                        </div>
                    </div>`;
                });
            } else {
                adviceHTML += `<p>${fullData["RAG sources"]}</p>`;
            }

            adviceHTML += `
                </div> <!-- Closing section-content-container -->
            </div>`; // Closing section-rag-sources
        } catch (error) {
            console.error("Error parsing RAG sources as JSON:", error);
            adviceHTML += `
            <div class="coaching-section section-rag-sources">
                 <div class="section-icon-container"><i class="fas fa-database"></i></div>
                 <div class="section-content-container">
                    <h5>RAG SOURCES</h5>
                    <p>${fullData["RAG sources"]}</p>
                 </div>
            </div>`;
        }
    }

    // Add any other fields that might be present
    Object.entries(fullData).forEach(([key, value]) => {
        // Skip fields we've already handled
        if (key !== "Message" && key !== "Response" && key !== "Knowledge" &&
            key !== "Reasoning" && key !== "Used Excerpts" &&
            key !== "RAG sources" && key !== "question") {
            adviceHTML += `
            <div class="coaching-section">
                 <div class="section-icon-container"><i class="fas fa-info-circle"></i></div>
                 <div class="section-content-container">
                    <h5>${key.toUpperCase()}</h5>
                    <p>${value}</p>
                 </div>
            </div>`;
        }
    });

    adviceElement.innerHTML = adviceHTML;
    coachingContainer.appendChild(adviceElement);

    // Add event listeners for expand buttons and source links
    const expandButtons = adviceElement.querySelectorAll('.expand-source-btn');
    expandButtons.forEach(button => {
        button.addEventListener('click', function () {
            const sourceIndex = this.getAttribute('data-source-index');
            const fullTextElement = document.getElementById(`source-full-text-${sourceIndex}`);
            if (fullTextElement) {
                if (fullTextElement.style.display === 'none') {
                    fullTextElement.style.display = 'block';
                    this.textContent = 'Collapse';
                } else {
                    fullTextElement.style.display = 'none';
                    this.textContent = 'Expand to view full text';
                }
            }
        });
    });

    // Add event listeners for source links
    const sourceLinks = adviceElement.querySelectorAll('.source-link');
    sourceLinks.forEach(link => {
        link.addEventListener('click', function (e) {
            e.preventDefault();
            const path = this.getAttribute('data-path');
            // No specific excerpt is associated with these RAG source links directly
            openDocumentViewer(path, null);
        });
    });

    // Also add the response to the conversation as a message from the salesperson
    addMessageToConversation({
        speaker: "Salesperson",
        message: fullData.Response,
        timestamp: new Date().toISOString()
    });
    scrollToBottom();
}


// Send a chat message from the input field
async function sendChatMessage() {
    const message = chatInput.value.trim();
    if (!message) return;

    // Create a message object
    const messageObj = {
        message_id: `custom-${Date.now()}`,
        speaker: 'Prospect', // User (Prospect) typed this message
        message: message,
        meeting_id: 'custom-meeting',
        timestamp: new Date().toISOString()
    };

    // Add to state and UI
    state.customMessages.push(messageObj);
    addMessageToConversation(messageObj);
    scrollToBottom();

    // Show typing indicator
    showTypingIndicator();


    // Send to backend for processing
    try {
        await sendMessageToKafka(message);
        chatInput.value = '';
    } catch (error) {
        console.error('Error sending message:', error);
        showError('Failed to send message. Please try again.');
    }
}

// Send message to Kafka via API
async function sendMessageToKafka(message) {
    try {
        // Check the cache first for an exact match
        const matchingQuestion = state.cachedQuestions.find(q => q.question.trim().toLowerCase() === message.trim().toLowerCase());

        if (matchingQuestion) {
            console.log('Found matching cached response for:', message);
            // Hide typing indicator after a 5 second delay for realism
            setTimeout(() => {
                hideTypingIndicator();
                // Use the cached response instead of calling the server
                displayCachedCoachingResponse(matchingQuestion);
            }, 5000);
            return { status: "cached" };
        }

        // Not found in cache, proceed with normal API call
        const response = await fetch('/api/send-message', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ message })
        });

        if (!response.ok) {
            throw new Error('Failed to send message to Kafka');
        }

        // Handle response - if it's a cached response from the server, display it immediately
        const result = await response.json();
        if (result.status === "cached" && result.full_data) {
            console.log('Server returned cached response for:', message);
            setTimeout(() => {
                hideTypingIndicator();
                displayCachedCoachingResponse(result.full_data);
            }, 5000);
        }

        return result;
    } catch (error) {
        console.error('Error sending message to Kafka:', error);
        throw error;
    }
}

// Send a suggested response
function sendSuggestedResponse(responseText) {
    chatInput.value = responseText;
    sendChatMessage();
}


// Add message to conversation container
function addMessageToConversation(message) {
    const messageDiv = document.createElement('div');
    messageDiv.className = `message message-${message.speaker.toLowerCase()}`;

    const html = `
        <div class="message-bubble">
            ${message.message}
        </div>
        <div class="message-metadata">
            <span class="message-speaker">${message.speaker}</span> |
            <span class="message-time">${formatTimestamp(message.timestamp)}</span>
        </div>
    `;

    messageDiv.innerHTML = html;
    conversationContainer.appendChild(messageDiv);
}

// Get coaching advice from API
async function getCoachingAdvice(messageText) {
    try {
        const response = await fetch(`/api/coaching-advice?message=${encodeURIComponent(messageText)}`);
        if (!response.ok) {
            throw new Error('Failed to fetch coaching advice');
        }

        const data = await response.json();

        if (data.has_advice) {
            displayCoachingAdvice(data.advice);

            // Highlight the current customer message
            const lastMessage = conversationContainer.lastChild;
            if (lastMessage) {
                lastMessage.classList.add('highlighted-message');
            }
        }
    } catch (error) {
        console.error('Error fetching coaching advice:', error);
    }
}

// Display coaching advice in the coaching container
function displayCoachingAdvice(advice) {
    // Hide the initial message if it exists
    const initialMessage = coachingContainer.querySelector('.initial-message');
    if (initialMessage) {
        initialMessage.style.display = 'none';
    }

    // Remove previous advice
    const prevAdvice = coachingContainer.querySelector('.coaching-advice');
    if (prevAdvice) {
        coachingContainer.removeChild(prevAdvice);
    }

    const adviceElement = document.createElement('div');
    adviceElement.className = 'coaching-advice new-advice';

    adviceElement.innerHTML = `
        <div class="coaching-section section-insight">
            <h5><i class="fas fa-lightbulb"></i> INSIGHT</h5>
            <p>${advice.insight}</p>
        </div>

        <div class="coaching-section section-opportunity">
            <h5><i class="fas fa-chart-line"></i> OPPORTUNITY</h5>
            <p>${advice.opportunity}</p>
        </div>

        <div class="coaching-section section-suggested-response">
            <h5><i class="fas fa-magic"></i> SUGGESTED RESPONSE</h5>
            <p>${advice.suggested_response}</p>
        </div>

        <div class="coaching-section section-knowledge">
            <h5><i class="fas fa-book"></i> KNOWLEDGE</h5>
            <p>${advice.knowledge}</p>
        </div>
    `;

    coachingContainer.appendChild(adviceElement);
}

// Display real-time coaching advice from WebSocket
function displayRealTimeCoachingAdvice(coaching) {
    // Hide typing indicator
    hideTypingIndicator();

    // Hide the initial message if it exists
    const initialMessage = coachingContainer.querySelector('.initial-message');
    if (initialMessage) {
        initialMessage.style.display = 'none';
    }

    // Remove previous advice
    const prevAdvice = coachingContainer.querySelector('.coaching-advice');
    if (prevAdvice) {
        coachingContainer.removeChild(prevAdvice);
    }

    const adviceElement = document.createElement('div');
    adviceElement.className = 'coaching-advice new-advice';

    // Log coaching data for debugging
    console.log("Received coaching data:", coaching);

    // Remove the wrapper div by not adding the header
    let adviceHTML = ``;

    // Get the coaching response content
    let coachingContent = coaching.coaching_response || "";
    console.log("Coaching content:", coachingContent);

    // Enable save button (becomes visible)
    const saveCacheBtn = document.getElementById('save-cache-btn');
    if (saveCacheBtn) {
        saveCacheBtn.style.opacity = '1';
        saveCacheBtn.disabled = false;
    }

    // Store last question and response for quick caching
    // Get the last user message (Prospect)
    const userMessages = conversationContainer.querySelectorAll('.message-prospect .message-bubble');
    const lastUserMessageElement = userMessages[userMessages.length - 1];
    if (lastUserMessageElement) {
        window.lastUserQuestion = lastUserMessageElement.textContent.trim();
    }

    try {
        let parsedResponse = null;

        // Attempt to parse the coaching_response field as JSON
        if (typeof coachingContent === 'string' && coachingContent.trim() !== '') {
            try {
                // Clean up potential markdown code blocks and common LLM formatting issues
                let cleanedContent = coachingContent;
                cleanedContent = cleanedContent.replace(/^```(?:json)?\s*\n?/, ''); // Remove opening ```json or ```
                cleanedContent = cleanedContent.replace(/\n?```\s*$/, ''); // Remove closing ```
                cleanedContent = cleanedContent.replace(/,\s*([}\]])/g, '$1'); // Remove trailing commas before closing brackets/braces
                cleanedContent = cleanedContent.replace(/(\w)\s*\n\s*(\w)/g, '$1 $2'); // Fix unnecessary newlines within strings (basic attempt)

                console.log("Attempting to parse cleaned content:", cleanedContent);
                parsedResponse = JSON.parse(cleanedContent);
                console.log("Successfully parsed coaching_response:", parsedResponse);

                // Store the parsed data for caching purposes (used by the save button)
                window.lastCoachingData = {
                    question: window.lastUserQuestion || "",
                    response: parsedResponse.suggested_response || "",
                    reasoning: parsedResponse.reasoning || "",
                    knowledge: parsedResponse.knowledge || "",
                    used_excerpts: parsedResponse.sources?.filter(s => s.used_excerpt).map(s => s.used_excerpt).join('\n\n') || "",
                    rag_sources: JSON.stringify(parsedResponse.sources || [])
                };

            } catch (parseError) {
                console.error("Failed to parse coaching_response as JSON:", parseError);
                console.error("Original coaching_response content:", coachingContent);
                // Keep parsedResponse as null if parsing fails
            }
        } else if (typeof coachingContent === 'object' && coachingContent !== null) {
            // If it's already an object (less likely based on schema, but possible)
            parsedResponse = coachingContent;
            console.log("coaching_response was already an object:", parsedResponse);
        }

        // Build HTML based on parsed data or show error/raw content
        if (parsedResponse) {
            // According to CLAUDE.md, there should be two main headings:
            // 1. SUGGESTED RESPONSE
            // 2. KNOWLEDGE

            // Display the suggested response section
            if (parsedResponse.suggested_response) {
                adviceHTML += `
                <div class="coaching-section section-suggested-response">
                    <div class="section-icon-container"><i class="fas fa-magic"></i></div>
                    <div class="section-content-container">
                        <h5>SUGGESTED RESPONSE</h5>
                        <p>${parsedResponse.suggested_response}</p>
                    </div>
                </div>`;
                // Also add the suggested response to the conversation
                addMessageToConversation({
                    speaker: "Salesperson",
                    message: parsedResponse.suggested_response,
                    timestamp: new Date().toISOString()
                });
                scrollToBottom();
            } else {
                 console.warn("Parsed response missing 'suggested_response' field.");
            }

            // Display the knowledge section if available
            if (parsedResponse.knowledge) {
                adviceHTML += `
                <div class="coaching-section section-knowledge">
                    <div class="section-icon-container"><i class="fas fa-book"></i></div>
                    <div class="section-content-container">
                        <h5>KNOWLEDGE</h5>
                        <p>${parsedResponse.knowledge}</p>
                    </div>
                </div>`;
            }

            // Display the reasoning section (optional)
            if (parsedResponse.reasoning) {
                adviceHTML += `
                <div class="coaching-section section-reasoning">
                    <div class="section-icon-container"><i class="fas fa-brain"></i></div>
                    <div class="section-content-container">
                        <h5>REASONING</h5>
                        <p>${parsedResponse.reasoning}</p>
                    </div>
                </div>`;
            }

            // Display the used excerpts and RAG sources sections
            if (parsedResponse.sources && Array.isArray(parsedResponse.sources)) {
                // --- Used Excerpts ---
                const usedSources = parsedResponse.sources.filter(source => source.used_excerpt && source.used_excerpt.trim() !== "");
                if (usedSources.length > 0) {
                    adviceHTML += `<div class="coaching-section section-used-excerpts">
                        <div class="section-icon-container"><i class="fas fa-file-alt"></i></div>
                        <div class="section-content-container">
                            <h5>RELEVANT EXCERPTS FROM RETRIEVED DOCUMENTS</h5>`;
                    usedSources.forEach(source => {
                        // Fix: Ensure proper path separator between path and title
                        const docPath = source.path ? (source.path.endsWith('/') ? source.path : source.path + '/') + source.title : source.title;
                        // Encode the excerpt to safely store it in the data attribute
                        const encodedExcerpt = encodeURIComponent(source.used_excerpt);
                        adviceHTML += `
                        <div class="source-item">
                            <div class="source-header">Document ${source.document_index}:
                                <a href="#" class="source-link excerpt-link" data-path="${docPath}" data-excerpt="${encodedExcerpt}">${source.title}</a>
                            </div>
                            <div class="source-excerpt">${marked.parse(source.used_excerpt)}</div>
                        </div>`;
                    });
                    adviceHTML += `
                        </div> <!-- Closing section-content-container -->
                    </div>`; // Closing section-used-excerpts
                } else {
                    console.log("No sources with 'used_excerpt' found.");
                }

                // --- RAG Sources (Full Text Expandable) ---
                adviceHTML += `<div class="coaching-section section-rag-sources">
                     <div class="section-icon-container"><i class="fas fa-database"></i></div>
                     <div class="section-content-container">
                        <h5>RAG SOURCES</h5>`;
                parsedResponse.sources.forEach(source => {
                    // Fix: Ensure proper path separator between path and title
                    const docPath = source.path ? (source.path.endsWith('/') ? source.path : source.path + '/') + source.title : source.title;
                    const previewText = source.full_text ? source.full_text.substring(0, 100) + '...' : '(No preview available)';
                    const fullTextHtml = source.full_text ? marked.parse(source.full_text) : '<p>(Full text not available)</p>';

                    adviceHTML += `
                    <div class="source-item">
                        <div class="source-header">
                            <a href="#" class="source-link" data-path="${docPath}">${source.title || 'Unknown Document'}</a>
                        </div>
                        <div class="source-preview">${previewText}</div>
                        <button class="btn btn-sm btn-outline-secondary expand-source-btn"
                                data-source-index="${source.document_index}">
                            Expand to view full text
                        </button>
                        <div class="source-full-text" id="source-full-text-${source.document_index}" style="display: none;">
                            ${fullTextHtml}
                        </div>
                    </div>`;
                });
                adviceHTML += `
                    </div> <!-- Closing section-content-container -->
                </div>`; // Closing section-rag-sources
            } else {
                console.warn("Parsed response missing 'sources' array or it's not an array.");
            }
        } else {
            // Fallback if parsing failed or coaching_response was empty/null
            console.log("Displaying fallback content because parsing failed or response was empty.");
            adviceHTML += `<div class="coaching-content alert alert-warning">
                <p>Could not display coaching advice. Raw response:</p>
                <pre><code>${coachingContent || '(empty)'}</code></pre>
            </div>`;
        }
    } catch (error) {
        // Catch unexpected errors during HTML building (less likely)
        console.error("Unexpected error building coaching advice HTML:", error);
        adviceHTML = `<div class="coaching-content alert alert-danger">
            <p>An unexpected error occurred while displaying coaching advice: ${error.message}</p>
        </div>`;
    }

    adviceElement.innerHTML = adviceHTML;
    coachingContainer.appendChild(adviceElement);

    // Add event listeners for expand buttons and source links
    const expandButtons = adviceElement.querySelectorAll('.expand-source-btn');
    expandButtons.forEach(button => {
        button.addEventListener('click', function () {
            const sourceIndex = this.getAttribute('data-source-index');
            const fullTextElement = document.getElementById(`source-full-text-${sourceIndex}`);
            if (fullTextElement) {
                if (fullTextElement.style.display === 'none') {
                    fullTextElement.style.display = 'block';
                    this.textContent = 'Collapse';
                } else {
                    fullTextElement.style.display = 'none';
                    this.textContent = 'Expand to view full text';
                }
            }
        });
    });

    // Add event listeners for source links
    // Add event listeners for ALL source links (including excerpt links)
    const sourceLinks = adviceElement.querySelectorAll('.source-link');
    sourceLinks.forEach(link => {
        link.addEventListener('click', function (e) {
            e.preventDefault();
            const path = this.getAttribute('data-path');
            let excerpt = null;
            // Check if it's an excerpt link and decode the excerpt text
            if (this.classList.contains('excerpt-link') && this.dataset.excerpt) {
                try {
                    excerpt = decodeURIComponent(this.dataset.excerpt);
                } catch (decodeError) {
                    console.error("Error decoding excerpt:", decodeError);
                }
            }
            openDocumentViewer(path, excerpt);
        });
    });
}

// Reset coaching advice display
function resetCoachingAdvice() {
    const initialMessage = coachingContainer.querySelector('.initial-message');
    if (initialMessage) {
        initialMessage.style.display = 'block';
    }

    // Remove all coaching advice elements
    const adviceElements = coachingContainer.querySelectorAll('.coaching-advice');
    adviceElements.forEach(element => {
        coachingContainer.removeChild(element);
    });
}

// Reset the entire conversation
function resetConversation() {
    // Clear the conversation container
    conversationContainer.innerHTML = '';

    // Reset coaching advice
    resetCoachingAdvice();

    // Reset state
    state.currentMessageIndex = -1;
    state.customMessages = [];

    // Stop auto play if active
    stopAutoPlay();
}

// Toggle auto play functionality
function toggleAutoPlay() {
    if (state.autoPlayInterval) {
        stopAutoPlay();
    } else {
        startAutoPlay();
    }
}

// Start auto play
function startAutoPlay() {
    // Update button appearance
    autoPlayBtn.textContent = 'Playing...';
    autoPlayBtn.classList.remove('btn-outline-primary');
    autoPlayBtn.classList.add('btn-danger');
    autoPlayBtn.disabled = true;

    // Check if we have cached questions
    if (!state.cachedQuestions || state.cachedQuestions.length < 3) {
        console.error('Not enough cached questions for auto play');
        alert('Not enough suggested questions available. Please try again later.');
        stopAutoPlay();
        return;
    }

    // Randomly select 3 different questions
    const shuffled = [...state.cachedQuestions].sort(() => 0.5 - Math.random());
    const selectedQuestions = shuffled.slice(0, 3);

    // Start the sequence
    playQuestionSequence(selectedQuestions, 0);
}

// Play a sequence of questions with appropriate delays
function playQuestionSequence(questions, index) {
    if (index >= questions.length) {
        // End of sequence
        stopAutoPlay();
        return;
    }

    const currentQuestion = questions[index];

    // 1. Display the question in chat
    addMessageToConversation({
        message_id: `auto-play-${Date.now()}`,
        speaker: 'Prospect', // User (Prospect) is asking the question
        message: currentQuestion.question,
        meeting_id: 'auto-play-interaction',
        timestamp: new Date().toISOString()
    });
    scrollToBottom();

    // 2. Show typing indicator
    showTypingIndicator();

    // 3. Wait 10 seconds, then display the coaching advice
    setTimeout(() => {
        // Display the coaching advice
        displayCachedCoachingResponse(currentQuestion);

        // Wait another 10 seconds before showing the next question
        setTimeout(() => {
            // Move to the next question
            playQuestionSequence(questions, index + 1);
        }, 10000);
    }, 10000);
}

// Stop auto play
function stopAutoPlay() {
    clearInterval(state.autoPlayInterval);
    state.autoPlayInterval = null;

    autoPlayBtn.textContent = 'Auto Play';
    autoPlayBtn.classList.remove('btn-danger');
    autoPlayBtn.classList.add('btn-outline-primary');
}


// Format timestamp for display
function formatTimestamp(timestamp) {
    const date = new Date(timestamp);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

// Scroll conversation container to bottom
function scrollToBottom() {
    conversationContainer.scrollTop = conversationContainer.scrollHeight;
}

// Show error message in conversation container
function showError(message) {
    const errorDiv = document.createElement('div');
    errorDiv.className = 'alert alert-danger';
    errorDiv.textContent = message;
    conversationContainer.appendChild(errorDiv);
}

// Document Viewer Functions
let documentModal;

// Function to open the document viewer with the specified document path
async function openDocumentViewer(path, excerptToHighlight = null) {
    console.log(`openDocumentViewer called with path: ${path} and excerpt: ${excerptToHighlight ? excerptToHighlight.substring(0, 50) + '...' : 'null'}`); // Verification Log 1
    try {
        // Initialize modal if not already done
        if (!documentModal) {
            documentModal = new bootstrap.Modal(document.getElementById('documentViewerModal'));
        }

        // Show loading state
        const documentContent = document.getElementById('documentContent');
        const documentPath = document.getElementById('documentPath');
        const modalTitle = document.getElementById('documentViewerModalLabel');

        documentContent.innerHTML = '<div class="text-center"><div class="spinner-border" role="status"></div><p class="mt-2">Loading document...</p></div>';
        documentPath.textContent = path;
        modalTitle.textContent = 'Loading...';

        // Show the modal
        documentModal.show();

        // Fetch the document content
        const response = await fetch(`/api/get-document/${encodeURIComponent(path)}`);

        if (!response.ok) {
            const errorData = await response.json();
            throw new Error(errorData.error || 'Failed to load document');
        }

        const data = await response.json();

        // Update modal with document content (rendered by marked.js)
        const rawContent = data.content;
        documentContent.innerHTML = marked.parse(rawContent);

        // Highlight the excerpt if provided, using mark.js
        // Highlight the excerpt if provided
        if (excerptToHighlight) {
            console.log("Excerpt provided, attempting highlight:", excerptToHighlight); // Verification Log 2

            // Clean the excerpt text (remove markdown, trim whitespace)
            // Create a temporary div to parse the excerpt markdown and get plain text
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = marked.parse(excerptToHighlight);
            const plainTextExcerpt = tempDiv.textContent.trim();
            console.log("Cleaned excerpt text for marking:", plainTextExcerpt);

            if (plainTextExcerpt) {
                 // Mark.js highlighting logic removed as per Subtask 25
                 console.log("Excerpt provided, but mark.js highlighting is disabled:", excerptToHighlight);
            } else {
                 console.warn("Excerpt text was empty after cleaning, skipping highlighting.");
            }
        } // Closing brace for if(excerptToHighlight)

        // Extract filename from path for the title
        const filename = path.split('/').pop();
        modalTitle.textContent = filename;
        documentPath.textContent = path;

    } catch (error) {
        console.error('Error loading or highlighting document:', error);

        // Show error in modal if it's open
        const documentContent = document.getElementById('documentContent');
        if (documentContent) {
            documentContent.innerHTML = `
                <div class="alert alert-danger">
                    <h5><i class="fas fa-exclamation-triangle"></i> Error Loading Document</h5>
                    <p>${error.message || 'An unknown error occurred'}</p>
                </div>
            `;
        }
    }
}


// --- Quick Save Feature ---

// Handle Ctrl+Shift+C shortcut
async function handleQuickSaveShortcut(event) {
    // Check if Ctrl, Shift, and C keys are pressed
    if (event.ctrlKey && event.shiftKey && event.key === 'C') {
        event.preventDefault(); // Prevent default browser behavior (like opening dev tools)
        console.log('Ctrl+Shift+C detected. Attempting to cache interaction...');

        // 1. Get the last user message (Prospect)
        const userMessages = conversationContainer.querySelectorAll('.message-prospect .message-bubble');
        const lastUserMessageElement = userMessages[userMessages.length - 1];
        const lastUserQuestion = lastUserMessageElement ? lastUserMessageElement.textContent.trim() : null;

        // 2. Get the last AI coaching response (Salesperson's suggested response)
        const lastAdviceElement = coachingContainer.querySelector('.coaching-advice:last-of-type');
        const lastAIResponseElement = lastAdviceElement ? lastAdviceElement.querySelector('.section-suggested-response p') : null;
        const lastAIResponse = lastAIResponseElement ? lastAIResponseElement.textContent.trim() : null;

        if (!lastUserQuestion || !lastAIResponse) {
            console.warn('Could not find the last user question or AI response. Caching aborted.');
            return;
        }

        console.log('Captured Question:', lastUserQuestion);
        console.log('Captured Response:', lastAIResponse);

        // 3. Extract any additional coaching data
        let coaching_data = {};

        // Get reasoning if it exists
        const reasoningElement = lastAdviceElement ? lastAdviceElement.querySelector('.section-reasoning p') : null;
        if (reasoningElement) {
            coaching_data.reasoning = reasoningElement.textContent.trim();
        }

        // Get used excerpts if they exist
        const usedExcerptsElement = lastAdviceElement ? lastAdviceElement.querySelector('.section-used-excerpts') : null;
        if (usedExcerptsElement) {
            coaching_data.used_excerpts = usedExcerptsElement.innerHTML.trim();
        }

        // Get RAG sources if they exist
        const ragSourcesElement = lastAdviceElement ? lastAdviceElement.querySelector('.section-rag-sources') : null;
        if (ragSourcesElement) {
            coaching_data.rag_sources = ragSourcesElement.innerHTML.trim();
        }

        // Get knowledge section if it exists
        const knowledgeElement = lastAdviceElement ? lastAdviceElement.querySelector('.section-knowledge p') : null;
        if (knowledgeElement) {
            coaching_data.knowledge = knowledgeElement.textContent.trim();
        }

        // 4. Send data to the backend
        try {
            const response = await fetch('/cache_interaction', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    question: lastUserQuestion,
                    response: lastAIResponse,
                    coaching_data: coaching_data
                }),
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const result = await response.json();

            if (result.status === 'success' && result.question) {
                console.log('Interaction successfully cached:', result.question);

                // Show notification to user
                alert('Conversation saved successfully! It will now appear in suggested questions.');

                // 5. Add the question to the suggested questions rotation with all its data
                // Avoid duplicates
                if (!state.cachedQuestions.some(q => q.question === result.question)) {
                    // Create a full data object with all fields
                    const fullCachedItem = {
                        question: result.question,
                        Response: lastAIResponse,
                        Reasoning: coaching_data.reasoning || '',
                        "Used Excerpts": coaching_data.used_excerpts || '',
                        "RAG sources": coaching_data.rag_sources || '',
                        Knowledge: coaching_data.knowledge || ''
                    };

                    state.cachedQuestions.push(fullCachedItem);
                    displaySuggestedQuestions(); // Refresh the displayed suggestions
                    console.log('Added question to suggestions rotation with full data');
                } else {
                    console.log('Question already exists in suggestions.');
                }
            } else {
                console.error('Failed to cache interaction. Server response:', result);
            }
        } catch (error) {
            console.error('Error sending cache request:', error);
        }
    }
}
// --- End Quick Save Feature ---

// --- Cache Manager Modal Functions ---

// Handle Ctrl+Shift+M shortcut to open the modal
function handleCacheManagerShortcut(event) {
    if (event.ctrlKey && event.shiftKey && event.key === 'M') {
        event.preventDefault();
        // console.log('Ctrl+Shift+M detected, calling openCacheManager...'); // Debug log removed
        openCacheManager();
    }
}

// Open the cache manager modal
function openCacheManager() {
    if (bootstrapCacheModal) { // Use the Bootstrap instance
        bootstrapCacheModal.show();
        loadCachedItems(); // Load items when opening
    } else {
        console.error("Bootstrap cache modal instance not initialized.");
    }
}

// Close the cache manager modal
function closeCacheManager() {
    if (bootstrapCacheModal) {
        bootstrapCacheModal.hide();
    } else if (cacheManagerModal) {
        // Fallback to direct DOM manipulation if bootstrap modal isn't available
        cacheManagerModal.style.display = 'none';
    }
}

// Load cached items from the backend and populate the table
async function loadCachedItems() {
    if (!cachedItemsTableBody) return;

    cachedItemsTableBody.innerHTML = '<tr><td colspan="3">Loading...</td></tr>'; // Show loading state

    try {
        const response = await fetch('/cached_responses');
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        const items = await response.json();

        cachedItemsTableBody.innerHTML = ''; // Clear loading/previous items

        if (!items || items.length === 0) {
            cachedItemsTableBody.innerHTML = '<tr><td colspan="3">No cached items found.</td></tr>';
            return;
        }

        // Only keep items with both a question/Message and a response/Response
        const validItems = items.filter(item =>
            (item.question || item.Message) &&
            (item.response || item.Response)
        );

        if (validItems.length === 0) {
            cachedItemsTableBody.innerHTML = '<tr><td colspan="3">No valid cached items found.</td></tr>';
            return;
        }

        validItems.forEach((item, index) => {
            const row = document.createElement('tr');
            // Check for Message/Response fields or question/response fields (handle both formats)
            const questionText = item.question || item.Message || '';
            const responseText = item.response || item.Response || '';

            // Skip rows with empty question or response
            if (!questionText || !responseText) return;

            row.innerHTML = `
                <td>${questionText}</td>
                <td>${responseText}</td>
                <td>
                    <button class="btn btn-danger btn-sm delete-cache-btn" data-index="${index}">
                        <i class="fas fa-trash-alt"></i> Delete
                    </button>
                </td>
            `;
            cachedItemsTableBody.appendChild(row);
        });

        // After loading items, also update the suggested questions
        if (validItems.length > 0) {
            // Update state.cachedQuestions with the new data
            state.cachedQuestions = validItems.map(item => {
                // Ensure consistent field names for frontend
                return {
                    question: item.question || item.Message || '',
                    Response: item.Response || item.response || '',
                    Reasoning: item.Reasoning || '',
                    "Used Excerpts": item["Used Excerpts"] || '',
                    "RAG sources": item["RAG sources"] || '',
                    Knowledge: item.Knowledge || ''
                };
            });

            // Refresh the suggested questions display
            displaySuggestedQuestions();
            console.log("Updated suggested questions from loaded items");
        }

    } catch (error) {
        console.error('Error loading cached items:', error);
        cachedItemsTableBody.innerHTML = '<tr><td colspan="3" class="text-danger">Error loading items.</td></tr>';

        // Try to recover by using any existing cached questions
        if (state.cachedQuestions && state.cachedQuestions.length > 0) {
            console.log("Using existing cached questions to populate table");
            cachedItemsTableBody.innerHTML = '';

            state.cachedQuestions.forEach((item, index) => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${item.question}</td>
                    <td>${item.Response}</td>
                    <td>
                        <button class="btn btn-danger btn-sm delete-cache-btn" data-index="${index}">
                            <i class="fas fa-trash-alt"></i> Delete
                        </button>
                    </td>
                `;
                cachedItemsTableBody.appendChild(row);
            });
        }
    }
}

// Handle clicks on delete buttons within the cache table
async function handleDeleteCacheItem(event) {
    if (!event.target.classList.contains('delete-cache-btn') && !event.target.closest('.delete-cache-btn')) {
        return; // Ignore clicks that are not on a delete button or its icon
    }

    const button = event.target.closest('.delete-cache-btn');
    const index = button.dataset.index;

    if (!confirm(`Are you sure you want to delete item #${parseInt(index) + 1}?`)) {
        return;
    }

    try {
        const response = await fetch(`/cached_responses/${index}`, {
            method: 'DELETE',
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const result = await response.json();

        if (result.status === 'success') {
            console.log('Item deleted successfully');
            // Refresh the table
            loadCachedItems();

            // Update the main suggested questions state and UI
            // Find the question that was deleted based on the index (assuming order is consistent)
            const deletedQuestionText = state.cachedQuestions[index]?.question;
            if (deletedQuestionText) {
                state.cachedQuestions = state.cachedQuestions.filter((_, i) => i !== parseInt(index));
                displaySuggestedQuestions(); // Refresh suggestions
                console.log(`Removed '${deletedQuestionText}' from suggestions.`);
            } else {
                 // If we can't find it by index easily, refetch all questions
                 console.warn('Could not determine deleted question by index, refetching all.');
                 fetchCachedQuestions();
            }

        } else {
            throw new Error(result.message || 'Failed to delete item');
        }

    } catch (error) {
        console.error('Error deleting cache item:', error);
        alert(`Error deleting item: ${error.message}`);
    }
}

// Handle form submission for adding a new cache item
async function handleAddCacheItem(event) {
    event.preventDefault(); // Prevent default form submission

    const question = newCacheQuestionInput.value.trim();
    const responseText = newCacheResponseInput.value.trim(); // Renamed to avoid conflict

    if (!question || !responseText) {
        alert('Please enter both a question and a response.');
        return;
    }

    try {
        const fetchResponse = await fetch('/cached_responses', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ question: question, response: responseText }), // Use responseText here
        });

        if (!fetchResponse.ok) {
            throw new Error(`HTTP error! status: ${fetchResponse.status}`);
        }

        const result = await fetchResponse.json();

        if (result.status === 'success' && result.item) {
            console.log('Item added successfully:', result.item);
            // Refresh the table
            loadCachedItems();
            // Clear the form
            addCacheForm.reset();

            // Update the main suggested questions state and UI
            // Avoid duplicates
            if (!state.cachedQuestions.some(q => q.question === result.item.question)) {
                state.cachedQuestions.push(result.item); // Add the new item
                displaySuggestedQuestions(); // Refresh suggestions
                console.log(`Added '${result.item.question}' to suggestions.`);
            }

            // Optional: Show success message
            alert('Item added successfully!');

        } else {
            throw new Error(result.message || 'Failed to add item');
        }

    } catch (error) {
        console.error('Error adding cache item:', error);
        alert(`Error adding item: ${error.message}`);
    }
}

// --- End Cache Manager Modal Functions ---
